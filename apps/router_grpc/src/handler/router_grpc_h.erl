-module(router_grpc_h).

-include("router_grpc.hrl").
-include("router_grpc_service_registry.hrl").
-include_lib("router_log/include/router_log.hrl").

-export([init/3, data/4, info/3, terminate/3, early_error/5, decode_data/2]).

-record(state, {
  stream_id :: cowboy_stream:streamid() | undefined,
  req :: cowboy_req:req() | undefined,
  handler_state :: term(),
  registry_details :: router_grpc_service_registry:details() | undefined,
  is_client_fin = false :: boolean(),
  is_server_fin = false :: boolean(),
  is_server_header_sent = false :: boolean(),
  data_buffer = <<>> :: binary()
}).
-type state() :: #state{}.

-define(fin_to_bool(Fin), case Fin of fin -> true; nofin -> false end).
-define(bool_to_fin(Bool), case Bool of true -> fin; false -> nofin end).

-define(incomplete_data(Compression, Len, Data), <<
  Compression:1/unsigned-integer-unit:8,
  Len:4/unsigned-integer-unit:8,
  Data/binary
>>).
-define(data(Compression, Len, Data, Rest), <<
  Compression:1/unsigned-integer-unit:8,
  Len:4/unsigned-integer-unit:8,
  Data:Len/binary-unit:8,
  Rest/binary
>>).
-define(uncompressed_data(Len, Data, Rest), ?data(0, Len, Data, Rest)).
-define(compressed_data(Len, Data, Rest), ?data(1, Len, Data, Rest)).

-type grpc_code() :: non_neg_integer().
-type grpc_message() :: unicode:unicode_binary().

-export_type([grpc_code/0, grpc_message/0]).



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
  router_log:component(router_grpc),
  case router_grpc_service_registry:lookup(Path) of
    {ok, #router_grpc_service_registry_definition_internal{module = Module} = Details} ->
      ?l_debug(#{text => "Internal gRPC request", what => init, details => #{
        service => Details#router_grpc_service_registry_definition_internal.service,
        method => Details#router_grpc_service_registry_definition_internal.method
      }}),
      {
        [],
        #state{stream_id = StreamId, req = Req, handler_state = Module:init(), registry_details = Details}
      };
    {error, undefined} ->
      ?l_debug(#{text => "Malformed gRPC request", what => init, details => #{path => Path}}),
      send_response(?grpc_code_unimplemented, ?grpc_message_unimplemented, #state{})
  end;

init(_StreamId, _Req, _Opts) ->
  router_log:component(router_grpc),
  {{response, <<"400">>, #{}, <<>>}, #state{}}.



-spec data(term(), term(), term(), term()) -> term().

data(StreamId, Fin, Data, #state{registry_details = Details, data_buffer = Buffer} = S0) ->
  IsFin = ?fin_to_bool(Fin),
  S1 = S0#state{stream_id = StreamId, is_client_fin = IsFin},
  case decode_data(<<Buffer/binary, Data/binary>>, Details) of
    {ok, {Pdu, Rest}} ->
      handle_grpc_pdu(Pdu, S1#state{data_buffer = Rest});
    {error, {grpc_error, GrpcCode, GrpcMessage}} ->
      ?l_debug(#{text => "gRPC payload decode error", what => data, result => error, details => #{
        data => Data, code => GrpcCode, message => GrpcMessage
      }}),
      send_response(GrpcCode, GrpcMessage, S1);
    {more, Data} ->
      {[], S1#state{data_buffer = <<Buffer/binary, Data/binary>>}}
  end.



-spec info(term(), term(), term()) -> term().
info(StreamId, Info, S0) ->
  ?l_debug(#{text => "INFO", what => info, details => #{stream_id => StreamId, info => Info}}),
  {[], S0}.



-spec terminate(term(), term(), term()) -> ok.
terminate(StreamId, Reason, _S0) ->
  ?l_debug(#{text => "TERMINATE", what => terminate, details => #{stream_id => StreamId, reason => Reason}}),
  ok.



-spec early_error(term(), term(), term(), term(), term()) -> term().
early_error(StreamId, Reason, PartialReq, Resp, Opts) ->
  ?l_debug(#{text => "EARLY_ERROR", what => early_error, details => #{
    stream_id => StreamId, reason => Reason, partial_req => PartialReq, resp => Resp, opts => Opts
  }}),
  Resp.



%% Internals


-spec decode_data(term(), term()) -> term().
decode_data(?incomplete_data(Compression, Len, Data) = Packet, _Definition)
when (1 == Compression orelse 0 == Compression) andalso byte_size(Data) < Len ->
  {more, Packet};

decode_data(?compressed_data(Len, _Data, _Rest), _Definition) ->
  {error, {grpc_error, ?grpc_code_unimplemented, ?grpc_message_unimplemented_compression}};

decode_data(
  ?uncompressed_data(Len, Data, Rest),
  #router_grpc_service_registry_definition_internal{definition = Definition, input = Input}
) ->
  try Definition:decode_msg(Data, Input) of
    Pdu -> {ok, {Pdu, Rest}}
  catch error:Reason ->
    ?l_debug(#{text => "gRPC payload decode error", what => data, result => error, details => #{
      data => Data, reason => Reason
    }}),
    {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload}}
  end;

decode_data(_Packet, _Definition) ->
  {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload}}.



encode_data(Pdu, #router_grpc_service_registry_definition_internal{definition = Definition, output = Output}) ->
  try Definition:encode_msg(Pdu, Output) of
    Data ->
      Len = byte_size(Data),
      {ok, ?uncompressed_data(Len, Data, <<>>)}
  catch error:Reason ->
    {error, Reason}
  end.



send_response(GrpcCode, GrpcMessage, S0) ->
  ?l_debug(#{text => "Sending gRPC response", what => send_response, result => ok, details => #{}}),
  {
    maybe_response_headers(S0) ++ [
      {trailers, #{
        ?grpc_header_code => integer_to_binary(GrpcCode),
        ?grpc_header_message => GrpcMessage
      }},
      stop
    ],
    S0#state{is_server_header_sent = true}
  }.



send_response(GrpcCode, GrpcMessage, Trailers, S0) when is_map(Trailers) ->
  ?l_debug(#{text => "Sending gRPC response plus trailers", what => send_response, result => ok, details => #{}}),
  {
    maybe_response_headers(S0) ++ [
      {trailers, maps:merge(Trailers, #{
        ?grpc_header_code => integer_to_binary(GrpcCode),
        ?grpc_header_message => GrpcMessage
      })},
      stop
    ],
    S0#state{is_server_header_sent = true}
  };

send_response(GrpcCode, GrpcMessage, Data, S0) when is_binary(Data) ->
  ?l_debug(#{text => "Sending gRPC response plus data", what => send_response, result => ok, details => #{}}),
  {
    maybe_response_headers(S0) ++ [
      {data, nofin, Data},
      {trailers, #{
        ?grpc_header_code => integer_to_binary(GrpcCode),
        ?grpc_header_message => GrpcMessage
      }},
      stop
    ],
    S0#state{is_server_header_sent = true}
  }.



send_response(GrpcCode, GrpcMessage, Trailers, Data, S0)
when is_map(Trailers), is_binary(Data) ->
  ?l_debug(#{text => "Sending gRPC response plus data/trailers", what => send_response, result => ok, details => #{}}),
  {
    maybe_response_headers(S0) ++ [
      {data, nofin, Data},
      {trailers, maps:merge(Trailers, #{
        ?grpc_header_code => integer_to_binary(GrpcCode),
        ?grpc_header_message => GrpcMessage
      })},
      stop
    ],
    S0#state{is_server_header_sent = true}
  }.



send_data(Data, #state{is_server_fin = ServerFin} = S0) ->
  ?l_debug(#{text => "Sending gRPC data", what => send_data, result => ok, details => #{}}),
  {
    maybe_response_headers(S0) ++ [
      {data, ?bool_to_fin(ServerFin), Data}
    ],
    S0#state{is_server_header_sent = true}
  }.



maybe_response_headers(#state{is_server_header_sent = false}) ->
  [
    {headers, <<"200">>, #{
      ?http2_header_content_type => <<"application/grpc+proto">>,
      ?grpc_header_user_agent => <<"grpc-erlang-lg-router/0.1.0">>
    }}
  ];

maybe_response_headers(_) -> [].




handle_grpc_pdu(Pdu, #state{
  handler_state = HS0,
  registry_details = #router_grpc_service_registry_definition_internal{
    module = Module, function = Function
  }
} = S0) ->
  case Module:Function(Pdu, HS0) of
    {ok, wait, HS1} ->
      handle_grpc_pdu_wait(S0#state{handler_state = HS1});
    {ok, {reply, ResponsePDU}, HS1} ->
      handle_grpc_pdu_send_response(ResponsePDU, S0#state{handler_state = HS1});
    {ok, {reply_fin, ResponsePDU}, HS1} ->
      handle_grpc_pdu_send_response(ResponsePDU, S0#state{handler_state = HS1, is_server_fin = true});
    {error, {grpc_error, GrpcCode, GrpcMessage}, HS1} ->
      handle_grpc_pdu_send_error(GrpcCode, GrpcMessage, S0#state{handler_state = HS1});
    {error, {grpc_error, GrpcCode, GrpcMessage, TrailersOrData}, HS1} ->
      handle_grpc_pdu_send_error(GrpcCode, GrpcMessage, TrailersOrData, S0#state{handler_state = HS1});
    {error, {grpc_error, GrpcCode, GrpcMessage, Trailers, Data}, HS1} ->
      handle_grpc_pdu_send_error(GrpcCode, GrpcMessage, Trailers, Data, S0#state{handler_state = HS1})
  end.



handle_grpc_pdu_wait(S0) ->
  {[], S0}.



handle_grpc_pdu_send_response(Pdu, #state{registry_details = Details} = S0) ->
  case {S0#state.is_client_fin, S0#state.is_server_fin, encode_data(Pdu, Details)} of
    {true, _, {ok, Data}} ->
      send_response(?grpc_code_ok, ?grpc_message_ok, Data, S0);
    {false, true, {ok, Data}} ->
      send_response(?grpc_code_ok, ?grpc_message_ok, Data, S0);
    {false, false, {ok, Data}} ->
      send_data(Data, S0);
    {_, _, {error, Reason}} ->
      ?l_error(#{
        text => "gRPC payload encode error", what => handle_grpc_pdu_send_response,
        result => error, details => #{reason => Reason}}
      ),
      handle_grpc_pdu_send_error(?grpc_code_internal, ?grpc_message_internal, S0)
  end.



handle_grpc_pdu_send_error(GrpcCode, GrpcMessage, S0) ->
  send_response(GrpcCode, GrpcMessage, S0#state{is_server_fin = true}).



handle_grpc_pdu_send_error(GrpcCode, GrpcMessage, TrailersOrData, S0) ->
  send_response(GrpcCode, GrpcMessage, TrailersOrData, S0#state{is_server_fin = true}).



handle_grpc_pdu_send_error(GrpcCode, GrpcMessage, Trailers, Data, S0) ->
  send_response(GrpcCode, GrpcMessage, Trailers, Data, S0#state{is_server_fin = true}).
