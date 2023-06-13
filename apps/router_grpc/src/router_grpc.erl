-module(router_grpc).

-include("router_grpc.hrl").
-include("router_grpc_service_registry.hrl").
-include_lib("router_log/include/router_log.hrl").

-export([unpack_decode_pdu/2, encode_pack_pdu/2]).
-export([unpack_data/1, pack_data/1]).
-export([decode_pdu/2, encode_pdu/2]).
-export([gen_agent_instance/0, fin_to_bool/1, bool_to_fin/1]).



%% Types



-type service_type() :: stateless | stateful.
-type service_package() :: binary().
-type service_name() :: binary().
-type fq_service_name() :: binary().
-type fq_method_name() :: binary().
-type method_name() :: binary().
-type service_maintenance() :: boolean().
-type endpoint_host() :: binary().
-type endpoint_port() :: 0..65535.
-type agent_id() :: binary().
-type agent_instance() :: binary().

-export_type([
  service_type/0, service_package/0, service_name/0, fq_service_name/0, fq_method_name/0, method_name/0,
  service_maintenance/0, endpoint_host/0, endpoint_port/0, agent_id/0, agent_instance/0
]).

-type definition() :: definition_internal() | definition_external().
-type definition_internal() :: #router_grpc_service_registry_definition_internal{}.
-type definition_external() :: #router_grpc_service_registry_definition_external{}.

-export_type([definition/0, definition_internal/0, definition_external/0]).



-define(data(Compression, Len, Data, Rest), <<
  Compression:1/unsigned-integer-unit:8,
  Len:4/unsigned-integer-unit:8,
  Data:Len/binary-unit:8,
  Rest/binary
>>).
-define(incomplete_data(Compression, Len, Data), <<
  Compression:1/unsigned-integer-unit:8,
  Len:4/unsigned-integer-unit:8,
  Data/binary
>>).
-define(uncompressed_data(Len, Data, Rest), ?data(0, Len, Data, Rest)).
-define(compressed_data(Len, Data, Rest), ?data(1, Len, Data, Rest)).



%% Interface



-spec unpack_decode_pdu(
  Data :: binary(),
  Definition :: definition_internal()
) ->
  typr:generic_return(
    OkRet :: {Pdu :: term(), Rest :: binary()},
    ErrorRet :: invalid_payload | unimplemented_compression
  ) | {more, Data :: binary()}.

unpack_decode_pdu(Data, Definition) ->
  case unpack_data(Data) of
    {ok, {Data, _Rest}} -> decode_pdu(Data, Definition);
    Etc -> Etc
  end.



-spec encode_pack_pdu(
  Pdu :: term(),
  Definition :: definition()
) ->
  typr:generic_return(
    OkRet :: binary(),
    ErrorRet :: term()
  ).

encode_pack_pdu(Pdu, Definition) ->
  case encode_pdu(Pdu, Definition) of
    {ok, Data} -> {ok, pack_data(Data)};
    Etc -> Etc
  end.



-spec unpack_data(Data :: binary()) ->
  typr:generic_return(
    OkRet :: {UnpackedData :: binary(), Rest :: binary()},
    ErrorRet :: unimplemented_compression
  ) | {more, Packet :: binary()}.

unpack_data(?compressed_data(Len, _Data, _Rest)) -> {error, unimplemented_compression};
unpack_data(?uncompressed_data(Len, Data, Rest)) -> {ok, {Data, Rest}};
unpack_data(?incomplete_data(_Compression, _Len, _Data) = Packet) -> {more, Packet}.



-spec pack_data(Data :: binary()) ->
  Ret :: binary().

pack_data(Data) ->
  Len = erlang:byte_size(Data),
  ?uncompressed_data(Len, Data, <<>>).



-spec decode_pdu(
  Data :: binary(),
  Definition :: definition_internal()
) ->
  typr:generic_return(
    OkRet :: {Pdu :: term(), Rest :: binary()},
    ErrorRet :: invalid_payload | unimplemented_compression
  ) | {more, Data :: binary()}.

decode_pdu(?compressed_data(Len, _Data, _Rest), _Definition) ->
  {error, unimplemented_compression};

decode_pdu(
  ?uncompressed_data(Len, Data, Rest),
  #router_grpc_service_registry_definition_internal{definition = Definition, input = Input}
) ->
  try Definition:decode_msg(Data, Input) of
    Pdu -> {ok, {Pdu, Rest}}
  catch error:Reason ->
    ?l_debug(#{text => "gRPC payload decode error", what => data, result => error, details => #{
      data => Data, reason => Reason
    }}),
    {error, invalid_payload}
  end;

decode_pdu(?incomplete_data(Compression, Len, Data) = Packet, _Definition)
when (1 == Compression orelse 0 == Compression) andalso byte_size(Data) < Len ->
  {more, Packet};

decode_pdu(_Packet, _Definition) ->
  {error, invalid_payload}.



-spec encode_pdu(
  Pdu :: term(),
  Definition :: definition()
) ->
  typr:generic_return(
    OkRet :: binary(),
    ErrorRet :: term()
  ).

encode_pdu(Pdu, #router_grpc_service_registry_definition_internal{definition = Definition, output = Output}) ->
  try Definition:encode_msg(Pdu, Output) of
    Data ->
      {ok, Data}
  catch error:Reason ->
    {error, Reason}
  end.



-spec gen_agent_instance() ->
  Ret :: agent_instance().

gen_agent_instance() ->
  list_to_binary(uuid:uuid_to_string(uuid:get_v4_urandom())).



-spec fin_to_bool(Fin :: cowboy_stream:fin()) ->
  Ret :: boolean().

fin_to_bool(fin) -> true;
fin_to_bool(nofin) -> false;
fin_to_bool(Etc) -> error({invalid_fin, Etc}).



-spec bool_to_fin(IsFin :: boolean()) ->
  Ret :: cowboy_stream:fin().

bool_to_fin(true) -> fin;
bool_to_fin(false) -> nofin.
