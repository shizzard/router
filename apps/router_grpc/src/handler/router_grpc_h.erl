-module(router_grpc_h).

-include("router_grpc.hrl").
-include("router_grpc_service_registry.hrl").
-include_lib("router_log/include/router_log.hrl").

-export([push_data/2]).
-export([init/3, data/4, info/3, terminate/3, early_error/5]).

-record(state, {
  stream_id :: cowboy_stream:streamid() | undefined,
  req :: cowboy_req:req() | undefined,
  handler_state :: term(),
  definition :: router_grpc:definition() | undefined,
  is_client_fin = false :: boolean(),
  is_server_fin = false :: boolean(),
  is_server_header_sent = false :: boolean(),
  data_buffer = <<>> :: binary()
}).
-type state() :: #state{}.

-define(fin_to_bool(Fin), case Fin of fin -> true; nofin -> false end).
-define(bool_to_fin(Bool), case Bool of true -> fin; false -> nofin end).

-type grpc_code() :: non_neg_integer().
-type grpc_message() :: unicode:unicode_binary().

-export_type([grpc_code/0, grpc_message/0]).



%% Messages



-define(msg_push_data(Pdu), {msg_push_data, Pdu}).



%% Handler types



-type handler_ret_ok_wait() :: wait.
-type handler_ret_ok_reply(PduT) :: {reply, PduT}.
-type handler_ret_ok_reply_fin(PduFinT) :: {reply_fin, PduFinT}.
-type handler_ret_error_grpc_error_simple(GrpcCodeT) :: {grpc_error, GrpcCodeT, grpc_message()}.
-type handler_ret_error_grpc_error_trailers(GrpcCodeT) :: {grpc_error, GrpcCodeT, grpc_message(), map()}.
-type handler_ret_error_grpc_error_data(GrpcCodeT) :: {grpc_error, GrpcCodeT, grpc_message(), binary()}.
-type handler_ret_error_grpc_error_trailers_and_data(GrpcCodeT) :: {grpc_error, GrpcCodeT, grpc_message(), map(), binary()}.
-type handler_ret_error_grpc_error(GrpcCodeT) ::
  handler_ret_error_grpc_error_simple(GrpcCodeT) |
  handler_ret_error_grpc_error_trailers(GrpcCodeT) |
  handler_ret_error_grpc_error_data(GrpcCodeT) |
  handler_ret_error_grpc_error_trailers_and_data(GrpcCodeT).
-type handler_ret(PduT, PduFinT, GrpcCodeT) :: typr:generic_return(
  OkRet :: handler_ret_ok_wait() | handler_ret_ok_reply(PduT) | handler_ret_ok_reply_fin(PduFinT),
  ErrorRet :: handler_ret_error_grpc_error(GrpcCodeT)
).
-export_type([
  handler_ret_ok_wait/0, handler_ret_ok_reply/1, handler_ret_ok_reply_fin/1,
  handler_ret_error_grpc_error_simple/1, handler_ret_error_grpc_error_trailers/1,
  handler_ret_error_grpc_error_data/1, handler_ret_error_grpc_error_trailers_and_data/1,
  handler_ret_error_grpc_error/1, handler_ret/3
]).


%% Interface



-spec push_data(
  Pdu :: term(),
  Req :: cowboy_req:req()
) ->
  typr:generic_return(ErrorRet :: term()).

push_data(Pdu, Req) ->
  cowboy_req:cast(?msg_push_data(Pdu), Req).



-spec init(
  StreamId :: cowboy_stream:streamid(),
  Req :: cowboy_req:req(),
  Opts :: cowboy:opts()
) ->
  Ret :: {
    Commands :: cowboy_stream:commands(),
    State :: state()
  }.

init(StreamId, #{
  version := 'HTTP/2',
  method := <<"POST">>,
  path := Path,
  headers := #{?http2_header_content_type := <<"application/grpc", _Rest/binary>>}
} = Req, _Opts) ->
  router_log:component(router_grpc_h),
  case router_grpc_service_registry:lookup_fqmn(Path) of
    {ok, [#router_grpc_service_registry_definition_internal{module = Module} = Definition]} ->
      ?l_debug(#{text => "Internal gRPC request", what => init, details => #{
        service => Definition#router_grpc_service_registry_definition_internal.service_name,
        method => Definition#router_grpc_service_registry_definition_internal.method
      }}),
      {
        [],
        #state{stream_id = StreamId, req = Req, handler_state = Module:init(Definition, Req), definition = Definition}
      };
    {error, undefined} ->
      ?l_debug(#{text => "Malformed gRPC request", what => init, details => #{path => Path}}),
      response_commands(?grpc_code_unimplemented, ?grpc_message_unimplemented, #state{})
  end;

init(_StreamId, _Req, _Opts) ->
  router_log:component(router_grpc),
  {{response, <<"400">>, #{}, <<>>}, #state{}}.



-spec data(
  StreamId :: cowboy_stream:streamid(),
  Fin :: cowboy_stream:fin(),
  Data :: binary(),
  State :: state()
) ->
  Ret :: {
    Commands :: cowboy_stream:commands(),
    State :: state()
  }.

data(StreamId, Fin, Data, #state{definition = Definition, data_buffer = Buffer} = S0) ->
  IsFin = ?fin_to_bool(Fin),
  S1 = S0#state{stream_id = StreamId, is_client_fin = IsFin},
  case router_grpc:unpack_data(<<Buffer/binary, Data/binary>>, Definition) of
    {ok, {Pdu, Rest}} ->
      handle_grpc_pdu(Pdu, S1#state{data_buffer = Rest});
    {more, Data} ->
      {[], S1#state{data_buffer = <<Buffer/binary, Data/binary>>}};
    {error, invalid_payload} ->
      ?l_debug(#{text => "gRPC payload decode error", what => data, result => error, details => #{
        reason => invalid_payload
      }}),
      {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload};
    {error, unimplemented_compression} ->
      ?l_debug(#{text => "gRPC payload decode error", what => data, result => error, details => #{
        reason => unimplemented_compression
      }}),
      {grpc_error, ?grpc_code_unimplemented, ?grpc_message_unimplemented_compression}
  end.



-spec info(
  StreamId :: cowboy_stream:streamid(),
  Info :: term(),
  State :: state()
) ->
  Ret :: {
    Commands :: cowboy_stream:commands(),
    State :: state()
  }.

info(StreamId, ?msg_push_data(Pdu), S0) ->
  case router_grpc:pack_data(Pdu, S0#state.definition) of
    {ok, Data} -> data_commands(Data, S0);
    {error, Reason} -> ?l_error(#{
      text => "Failed to pack pushed data", what => info, details => #{
        stream_id => StreamId, pdu => Pdu, reason => Reason
      }
    })
  end;

info(StreamId, Info, S0) ->
  ?l_debug(#{text => "INFO", what => info, details => #{stream_id => StreamId, info => Info}}),
  {[], S0}.



-spec terminate(
  StreamId :: cowboy_stream:streamid(),
  Reason :: term(),
  State :: state()
) ->
  Ret :: term().

terminate(StreamId, Reason, _S0) ->
  ?l_debug(#{text => "TERMINATE", what => terminate, details => #{stream_id => StreamId, reason => Reason}}),
  ok.



-spec early_error(
  StreamId :: cowboy_stream:streamid(),
  Reason :: cowboy_stream:reason(),
  PartialReq :: cowboy_req:req(),
  Resp :: cowboy_stream:resp_command(),
  Opts :: cowboy:opts()
) ->
  Ret :: cowboy_stream:resp_command().

early_error(StreamId, Reason, PartialReq, Resp, Opts) ->
  ?l_debug(#{text => "EARLY_ERROR", what => early_error, details => #{
    stream_id => StreamId, reason => Reason, partial_req => PartialReq, resp => Resp, opts => Opts
  }}),
  Resp.



%% Internals



response_commands(GrpcCode, GrpcMessage, S0) ->
  {Headers, S1} = maybe_response_headers(S0),
  {Headers ++ [
    {trailers, #{
      ?grpc_header_code => integer_to_binary(GrpcCode),
      ?grpc_header_message => GrpcMessage
    }},
    stop
  ], S1}.



response_commands(GrpcCode, GrpcMessage, Data, S0) ->
  {Headers, S1} = maybe_response_headers(S0),
  {Headers ++ [
    {data, nofin, Data},
    {trailers, #{
      ?grpc_header_code => integer_to_binary(GrpcCode),
      ?grpc_header_message => GrpcMessage
    }},
    stop
  ], S1}.



data_commands(Data, #state{is_server_fin = ServerFin} = S0) ->
  {Headers, S1} = maybe_response_headers(S0),
  {Headers ++ [
    {data, ?bool_to_fin(ServerFin), Data}
  ], S1}.



error_commands(GrpcCode, GrpcMessage, S0) ->
  {Headers, S1} = maybe_response_headers(S0),
  {Headers ++ [
    {trailers, #{
      ?grpc_header_code => integer_to_binary(GrpcCode),
      ?grpc_header_message => GrpcMessage
    }},
    stop
  ], S1}.



error_commands(GrpcCode, GrpcMessage, Trailers, S0) ->
  {Headers, S1} = maybe_response_headers(S0),
  {Headers ++ [
    {trailers, maps:merge(Trailers, #{
      ?grpc_header_code => integer_to_binary(GrpcCode),
      ?grpc_header_message => GrpcMessage
    })},
    stop
  ], S1}.



error_commands(GrpcCode, GrpcMessage, Trailers, Data, S0) ->
  {Headers, S1} = maybe_response_headers(S0),
  {Headers ++ [
    {data, nofin, Data},
    {trailers, maps:merge(Trailers, #{
      ?grpc_header_code => integer_to_binary(GrpcCode),
      ?grpc_header_message => GrpcMessage
    })},
    stop
  ], S1}.



wait_commands(S0) -> {[], S0}.



maybe_response_headers(#state{is_server_header_sent = false} = S0) ->
  {[
    {headers, <<"200">>, #{
      ?http2_header_content_type => <<"application/grpc+proto">>,
      ?grpc_header_user_agent => <<"grpc-erlang-lg-router/0.1.0">>
    }}
  ], S0#state{is_server_header_sent = true}};

maybe_response_headers(S0) -> {[], S0}.



handle_grpc_pdu(Pdu, #state{
  handler_state = HS0,
  definition = #router_grpc_service_registry_definition_internal{
    module = Module, function = Function
  }
} = S0) ->
  try Module:Function(Pdu, HS0) of
    {ok, wait, HS1} ->
      wait_commands(S0#state{handler_state = HS1});
    {ok, {reply, ResponsePDU}, HS1} ->
      handle_grpc_pdu_send_response(ResponsePDU, S0#state{handler_state = HS1});
    {ok, {reply_fin, ResponsePDU}, HS1} ->
      handle_grpc_pdu_send_response(ResponsePDU, S0#state{handler_state = HS1, is_server_fin = true});
    {error, {grpc_error, GrpcCode, GrpcMessage}, HS1} ->
      error_commands(GrpcCode, GrpcMessage, S0#state{handler_state = HS1});
    {error, {grpc_error, GrpcCode, GrpcMessage, TrailersOrData}, HS1} ->
      error_commands(GrpcCode, GrpcMessage, TrailersOrData, S0#state{handler_state = HS1});
    {error, {grpc_error, GrpcCode, GrpcMessage, Trailers, Data}, HS1} ->
      error_commands(GrpcCode, GrpcMessage, Trailers, Data, S0#state{handler_state = HS1})
  catch T:R:S ->
    ?l_error(#{
      text => "gRPC callback failure", what => handle_grpc_pdu,
      result => error, details => #{type => T, reason => R, stacktrace => S}}
    ),
    error_commands(?grpc_code_internal, ?grpc_message_internal, S0#state{is_server_fin = true})
  end.



handle_grpc_pdu_send_response(Pdu, #state{definition = Details} = S0) ->
  case {S0#state.is_client_fin, S0#state.is_server_fin, router_grpc:pack_data(Pdu, Details)} of
    {true, _, {ok, Data}} ->
      response_commands(?grpc_code_ok, ?grpc_message_ok, Data, S0);
    {false, true, {ok, Data}} ->
      response_commands(?grpc_code_ok, ?grpc_message_ok, Data, S0);
    {false, false, {ok, Data}} ->
      data_commands(Data, S0);
    {_, _, {error, Reason}} ->
      ?l_error(#{
        text => "gRPC payload encode error", what => handle_grpc_pdu_send_response,
        result => error, details => #{reason => Reason}}
      ),
      error_commands(?grpc_code_internal, ?grpc_message_internal, S0)
  end.
