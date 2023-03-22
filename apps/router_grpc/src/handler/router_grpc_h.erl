-module(router_grpc_h).

-include("router_grpc.hrl").
-include("router_grpc_registry.hrl").
-include_lib("router_log/include/router_log.hrl").

-export([init/3, data/4, info/3, terminate/3, early_error/5, decode_data/2]).

-record(state, {
  stream_id :: cowboy_stream:streamid() | undefined,
  req :: cowboy_req:req() | undefined,
  registry_definition :: router_grpc_registry:definition() | undefined,
  is_client_fin :: boolean(),
  is_server_fin = false :: boolean(),
  handler_state :: term() | undefined,
  data_buffer = <<>> :: binary()
}).

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
-define(non_compressed_data(Len, Data, Rest), ?data(0, Len, Data, Rest)).
-define(compressed_data(Len, Data, Rest), ?data(1, Len, Data, Rest)).

-type grpc_code() :: non_neg_integer().
-type grpc_message() :: unicode:unicode_binary().

-export_type([grpc_code/0, grpc_message/0]).



%% Interface



-spec init(term(), term(), term()) -> ok.

init(StreamId, #{
  version := 'HTTP/2',
  method := <<"POST">>,
  path := Path,
  headers := #{?grpc_header_content_type := <<"application/grpc", _Rest/binary>>}
} = Req, _Opts) ->
  router_log:component(router_grpc),
  case router_grpc_registry:lookup(Path) of
    {ok, #router_grpc_registry_definition{module = Module} = Definition} ->
      ?l_debug(#{text => "gRPC request", what => init, details => #{
        service => Definition#router_grpc_registry_definition.service,
        method => Definition#router_grpc_registry_definition.method
      }}),
      {ok, HS0} = Module:init(),
      {[], #state{stream_id = StreamId, req = Req, registry_definition = Definition, handler_state = HS0}};
    {error, undefined} ->
      ?l_debug(#{text => "Malformed gRPC request", what => init, details => #{path => Path}}),
      {
        response_commands(?grpc_code_unimplemented, ?grpc_message_unimplemented),
        #state{}
      }
  end;

init(_StreamId, _Req, _Opts) ->
  router_log:component(router_grpc),
  {{response, <<"400">>, #{}, <<>>}, #state{}}.



-spec data(term(), term(), term(), term()) -> term().

data(StreamId, Fin, Data, #state{registry_definition = Definition, data_buffer = Buffer} = S0) ->
  IsFin = ?fin_to_bool(Fin),
  S1 = S0#state{stream_id = StreamId, is_client_fin = IsFin},
  case decode_data(<<Buffer/binary, Data/binary>>, Definition) of
    {ok, {PDU, Rest}} ->
      handle_grpc_pdu(PDU, S1#state{data_buffer = Rest});
    {error, {grpc_error, GrpcCode, GrpcMessage}} ->
      ?l_debug(#{text => "gRPC payload decode error", what => data, result => error, details => #{
        data => Data, code => GrpcCode, message => GrpcMessage
      }}),
      {response_commands(GrpcCode, GrpcMessage), S1};
    {error, Reason} ->
      ?l_debug(#{text => "gRPC payload decode error", what => data, result => error, details => #{
        data => Data, reason => Reason
      }}),
      {response_commands(?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload), S1};
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
  ?non_compressed_data(Len, Data, Rest),
  #router_grpc_registry_definition{definition = Definition, input = Input}
) ->
  try Definition:decode_msg(Data, Input) of
    PDU -> {ok, {PDU, Rest}}
  catch error:Reason ->
    {error, Reason}
  end;

decode_data(_Packet, _Definition) ->
  {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload}}.



encode_data(PDU, #router_grpc_registry_definition{definition = Definition, output = Output}) ->
  try Definition:encode_msg(PDU, Output) of
    Data ->
      Len = byte_size(Data),
      {ok, ?non_compressed_data(Len, Data, <<>>)}
  catch error:Reason ->
    {error, Reason}
  end.



response_commands(GrpcCode, GrpcMessage) ->
  [
    {headers, <<"200">>, #{
      ?grpc_header_content_type => <<"application/grpc+proto">>,
      ?grpc_header_user_agent => <<"grpc-erlang-lg-router/0.1.0">>
    }},
    {trailers, #{
      ?grpc_header_code => integer_to_binary(GrpcCode),
      ?grpc_header_message => GrpcMessage
    }}
  ].



response_commands(GrpcCode, GrpcMessage, Data) ->
  [
    {headers, <<"200">>, #{
      ?grpc_header_content_type => <<"application/grpc+proto">>,
      ?grpc_header_user_agent => <<"grpc-erlang-lg-router/0.1.0">>
    }},
    {data, nofin, Data},
    {trailers, #{
      ?grpc_header_code => integer_to_binary(GrpcCode),
      ?grpc_header_message => GrpcMessage
    }}
  ].



data_commands(Data, ServerFin) ->
  [data, ?bool_to_fin(ServerFin), Data].




handle_grpc_pdu(PDU, #state{
  registry_definition = #router_grpc_registry_definition{
    module = Module, function = Function
  },
  handler_state = HS0
} = S0) ->
  case Module:Function(PDU, HS0) of
    {ok, {ResponsePDU, HS1}} ->
      handle_grpc_pdu_send_response(ResponsePDU, S0#state{handler_state = HS1});
    {ok, {fin, ResponsePDU, HS1}} ->
      handle_grpc_pdu_send_response(ResponsePDU, S0#state{is_server_fin = true, handler_state = HS1});
    {error, {GrpcCode, GrpcMessage, HS1}} ->
      handle_grpc_pdu_send_error(GrpcCode, GrpcMessage, S0#state{handler_state = HS1})
  end.



handle_grpc_pdu_send_response(PDU, #state{registry_definition = Definition} = S0) ->
  case {S0#state.is_client_fin, S0#state.is_server_fin, encode_data(PDU, Definition)} of
    {true, _, {ok, Data}} ->
      {response_commands(?grpc_code_ok, ?grpc_message_ok, Data), S0};
    {false, ServerFin, {ok, Data}} ->
      {data_commands(Data, ServerFin), S0};
    {_, _, {error, Reason}} ->
      ?l_error(#{
        text => "gRPC payload encode error", what => handle_grpc_pdu_send_response,
        result => error, details => #{reason => Reason}}
      ),
      handle_grpc_pdu_send_error(?grpc_code_internal, ?grpc_message_internal, S0)
  end.



handle_grpc_pdu_send_error(GrpcCode, GrpcMessage, S0) ->
  {response_commands(GrpcCode, GrpcMessage), S0}.
