-module(rtgw_grpc_h).

-include_lib("rtgw_grpc/include/rtgw_grpc.hrl").
-include_lib("rtgw_log/include/rtgw_log.hrl").

-export([push_headers/4, push_data/3, push_trailers/2, push_internal_pdu/2]).
-export([init/3, data/4, info/3, terminate/3, early_error/5]).

-record(state, {
  stream_id :: cowboy_stream:streamid() | undefined,
  req :: cowboy_req:req() | undefined,
  handler_state :: term(),
  module :: atom() | undefined,
  function :: atom() | undefined,
  is_client_fin = false :: boolean(),
  is_server_fin = false :: boolean(),
  is_server_header_sent = false :: boolean(),
  data_buffer = <<>> :: binary()
}).
-type state() :: #state{}.

-type grpc_code() :: non_neg_integer().
-type grpc_message() :: unicode:unicode_binary().

-export_type([grpc_code/0, grpc_message/0]).



%% Defaults



-define(default_headers, #{
  ?http2_header_content_type => <<"application/grpc+proto">>,
  ?grpc_header_user_agent => <<"grpc-erlang-lg-rtgw/0.1.0">>
}).

-define(default_trailers, #{}).



%% Messages



-define(msg_push_headers(IsFin, Status, Headers), {msg_push_headers, IsFin, Status, Headers}).
-define(msg_push_data(IsFin, Data), {msg_push_data, IsFin, Data}).
-define(msg_push_trailers(Trailers), {msg_push_trailers, Trailers}).
-define(msg_push_internal_pdu(Pdu), {msg_push_internal_pdu, Pdu}).



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



-spec push_headers(
  IsFin :: boolean(),
  Status :: cowboy_req:status(),
  Headers :: rtgw_grpc_client:grpc_headers(),
  Req :: cowboy_req:req()
) ->
  typr:generic_return(ErrorRet :: term()).

push_headers(IsFin, Status, Headers, Req) ->
  cowboy_req:cast(?msg_push_headers(IsFin, Status, Headers), Req).



-spec push_data(
  IsFin :: boolean(),
  Data :: binary(),
  Req :: cowboy_req:req()
) ->
  typr:generic_return(ErrorRet :: term()).

push_data(IsFin, Data, Req) ->
  cowboy_req:cast(?msg_push_data(IsFin, Data), Req).



-spec push_trailers(
  Trailers :: rtgw_grpc_client:grpc_headers(),
  Req :: cowboy_req:req()
) ->
  typr:generic_return(ErrorRet :: term()).

push_trailers(Trailers, Req) ->
  cowboy_req:cast(?msg_push_trailers(Trailers), Req).



-spec push_internal_pdu(
  Pdu :: term(),
  Req :: cowboy_req:req()
) ->
  typr:generic_return(ErrorRet :: term()).

push_internal_pdu(Pdu, Req) ->
  cowboy_req:cast(?msg_push_internal_pdu(Pdu), Req).



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
  rtgw_log:component(rtgw_grpc_h),
  ok = quickrand:seed(),
  case Path of
    <<"/lg.service.demo.rtgw.GatewayService/SpawnTunnel">> ->
      init_handler(StreamId, Req, rtgw_grpc_handler_gateway, spawn_tunnel);
    <<"/lg.service.demo.rtgw.TunnelService/GetStats">> ->
      init_handler(StreamId, Req, rtgw_grpc_handler_tunnel, get_stats);
    _ ->
      ?l_debug(#{text => "Unknown virtual service called", what => init, details => #{path => Path}}),
      unary_response_commands(?grpc_code_not_found, ?grpc_message_not_found, #state{})
  end;

init(_StreamId, _Req, _Opts) ->
  rtgw_log:component(rtgw_grpc),
  {{response, <<"400">>, #{}, <<>>}, #state{}}.



init_handler(StreamId, Req, Module, Function) ->
  ?l_debug(#{text => "gRPC handler init", what => init, details => #{module => Module, function => Function}}),
  HS0 = Module:init(Function, Req),
  wait_commands(#state{stream_id = StreamId, req = Req, handler_state = HS0, module = Module, function = Function}).



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

data(StreamId, Fin, Data, #state{module = Module, function = Function, data_buffer = Buffer} = S0) ->
  ?l_debug(#{text => "gRPC payload", what => data, details => #{
    fin => Fin, data => Data
  }}),
  IsFin = rtgw_grpc:fin_to_bool(Fin),
  S1 = S0#state{stream_id = StreamId, is_client_fin = IsFin},
  case rtgw_grpc:unpack_decode_pdu(<<Buffer/binary, Data/binary>>, mf_to_definition(Module, Function), mf_to_type_in(Module, Function)) of
    {ok, {Pdu, Rest}} ->
      handle_grpc_pdu(Pdu, S1#state{data_buffer = Rest});
    {more, Data} ->
      {[], S1#state{data_buffer = <<Buffer/binary, Data/binary>>}};
    {error, invalid_payload} ->
      ?l_debug(#{text => "gRPC payload decode error", what => data, result => error, details => #{
        reason => invalid_payload, module => Module, function => Function
      }}),
      error_commands(?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, S0);
    {error, unimplemented_compression} ->
      ?l_debug(#{text => "gRPC payload decode error", what => data, result => error, details => #{
        reason => unimplemented_compression
      }}),
      error_commands(?grpc_code_unimplemented, ?grpc_message_unimplemented_compression, S0)
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

info(_StreamId, ?msg_push_headers(IsFin, _Status, Headers), S0) ->
  ?l_dev(#{text => "HEADERS", details => Headers}),
  headers_commands(S0#state{is_server_fin = IsFin});

info(_StreamId, ?msg_push_data(IsFin, Data), S0) ->
  ?l_dev(#{text => "DATA", details => Data}),
  data_commands(rtgw_grpc:pack_data(Data), S0#state{is_server_fin = IsFin});

info(_StreamId, ?msg_push_trailers(Trailers), S0) ->
  ?l_dev(#{text => "TRAILERS", details => Trailers}),
  GrpcCode = maybe_get_grpc_code(Trailers),
  GrpcMessage = maybe_get_grpc_message(Trailers),
  trailers_commands(GrpcCode, GrpcMessage, Trailers, S0);

info(StreamId, Info, S0) ->
  ?l_dev(#{text => "INFO", what => info, details => #{stream_id => StreamId, info => Info}}),
  {[], S0}.



-spec terminate(
  StreamId :: cowboy_stream:streamid(),
  Reason :: term(),
  State :: state()
) ->
  Ret :: term().

terminate(StreamId, Reason, _S0) ->
  ?l_dev(#{text => "TERMINATE", what => terminate, details => #{stream_id => StreamId, reason => Reason}}),
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
  ?l_dev(#{text => "EARLY_ERROR", what => early_error, details => #{
    stream_id => StreamId, reason => Reason, partial_req => PartialReq, resp => Resp, opts => Opts
  }}),
  Resp.



%%



mf_to_definition(rtgw_grpc_handler_gateway, _) -> gateway_definitions;
mf_to_definition(rtgw_grpc_handler_tunnel, _) -> tunnel_definitions.

mf_to_type_in(rtgw_grpc_handler_gateway, spawn_tunnel) -> 'lg.service.demo.rtgw.SpawnTunnelRq';
mf_to_type_in(rtgw_grpc_handler_tunnel, get_stats) -> 'lg.service.demo.rtgw.GetStatsRq'.

mf_to_type_out(rtgw_grpc_handler_gateway, spawn_tunnel) -> 'lg.service.demo.rtgw.SpawnTunnelRs';
mf_to_type_out(rtgw_grpc_handler_tunnel, get_stats) -> 'lg.service.demo.rtgw.GetStatsRs'.



%% Response commands functions; to be used for generating the response



headers_commands(S0) -> response_headers(S0).



data_commands(Data, S0) ->
  {HeadersCommands, S1} = response_headers(S0),
  {DataCommands, S2} = response_data(Data, S1),
  Commands = HeadersCommands ++ DataCommands,
  {Commands, S2}.



trailers_commands(GrpcCode, GrpcMessage, Trailers, S0) ->
  response_trailers(GrpcCode, GrpcMessage, Trailers, S0).



error_commands(GrpcCode, GrpcMessage, S0) ->
  unary_response_commands(GrpcCode, GrpcMessage, S0).



error_commands(GrpcCode, GrpcMessage, Trailers, S0) ->
  unary_response_commands(GrpcCode, GrpcMessage, Trailers, S0).



unary_response_commands(GrpcCode, GrpcMessage, S0) ->
  {HeadersCommands, S1} = response_headers(S0),
  {TrailersCommands, S2} = response_trailers(GrpcCode, GrpcMessage, S1),
  Commands = HeadersCommands ++ TrailersCommands ++ [stop],
  {Commands, S2}.



unary_response_commands(GrpcCode, GrpcMessage, Data, S0) when is_binary(Data) ->
  {HeadersCommands, S1} = response_headers(S0),
  {DataCommands, S2} = response_data(Data, S1#state{is_server_fin = false}),
  {TrailersCommands, S3} = response_trailers(GrpcCode, GrpcMessage, S2),
  Commands = HeadersCommands ++ DataCommands ++ TrailersCommands ++ [stop],
  {Commands, S3};

unary_response_commands(GrpcCode, GrpcMessage, Trailers, S0) when is_map(Trailers) ->
  {HeadersCommands, S1} = response_headers(S0),
  {TrailersCommands, S2} = response_trailers(GrpcCode, GrpcMessage, Trailers, S1),
  Commands = HeadersCommands ++ TrailersCommands ++ [stop],
  {Commands, S2}.



wait_commands(S0) -> {[], S0}.



%% Response commands functions; not to be used directly, use the '_commands' functions



response_headers(#state{
  is_server_header_sent = false
} = S0) ->
  {
    [{headers, <<"200">>, ?default_headers}],
    S0#state{is_server_header_sent = true}
  };

response_headers(S0) -> {[], S0}.



response_data(Data, #state{is_server_fin = ServerFin} = S0) ->
  {[{data, rtgw_grpc:bool_to_fin(ServerFin), Data}], S0}.



response_trailers(GrpcCode, GrpcMessage, S0) ->
  response_trailers(GrpcCode, GrpcMessage, #{}, S0).



response_trailers(GrpcCode, GrpcMessage, Trailers, S0) ->
  {
    [{trailers, maps:merge(Trailers, #{
      ?grpc_header_code => grpc_code_to_binary(GrpcCode),
      ?grpc_header_message => GrpcMessage
    })}],
    S0
  }.



%% Internals



handle_grpc_pdu(Pdu, #state{handler_state = HS0, module = Module, function = Function} = S0) ->
  ?l_dev(#{
    text => "gRPC callback call", what => handle_grpc_pdu,
    details => #{pdu => Pdu}
  }),
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
      error_commands(GrpcCode, GrpcMessage, TrailersOrData, S0#state{handler_state = HS1})
  catch T:R:S ->
    ?l_error(#{
      text => "gRPC callback failure", what => handle_grpc_pdu,
      result => error, details => #{type => T, reason => R, stacktrace => S}}
    ),
    error_commands(?grpc_code_internal, ?grpc_message_internal, S0#state{is_server_fin = true})
  end.



handle_grpc_pdu_send_response(Pdu, #state{module = Module, function = Function} = S0) ->
  case {S0#state.is_client_fin, S0#state.is_server_fin, rtgw_grpc:encode_pack_pdu(Pdu, mf_to_definition(Module, Function), mf_to_type_out(Module, Function))} of
    {true, _, {ok, Data}} ->
      unary_response_commands(?grpc_code_ok, ?grpc_message_ok, Data, S0);
    {false, true, {ok, Data}} ->
      unary_response_commands(?grpc_code_ok, ?grpc_message_ok, Data, S0);
    {false, false, {ok, Data}} ->
      data_commands(Data, S0);
    {_, _, {error, Reason}} ->
      ?l_error(#{
        text => "gRPC payload encode error", what => handle_grpc_pdu_send_response,
        result => error, details => #{reason => Reason}}
      ),
      error_commands(?grpc_code_internal, ?grpc_message_internal, S0)
  end.



grpc_code_to_binary(GrpcCode) when is_binary(GrpcCode) -> GrpcCode;
grpc_code_to_binary(GrpcCode) when is_integer(GrpcCode) -> integer_to_binary(GrpcCode);
grpc_code_to_binary(GrpcCode) -> error({invalid_grpc_code, GrpcCode}).



maybe_get_grpc_code(#{?grpc_header_code := GrpcCode}) -> GrpcCode;
maybe_get_grpc_code(Trailers) ->
  ?l_warning(#{
    text => "Upstream service is missing the gRPC code in its response, sending code OK (0)",
    what => maybe_get_grpc_code, details => #{trailers => Trailers}
  }),
  ?grpc_code_ok.



maybe_get_grpc_message(#{?grpc_header_message := GrpcCode}) -> GrpcCode;
maybe_get_grpc_message(Trailers) ->
  ?l_warning(#{
    text => "Upstream service is missing the gRPC message in its response, sending default message (empty)",
    what => maybe_get_grpc_message, details => #{trailers => Trailers}
  }),
  ?grpc_message_ok.
