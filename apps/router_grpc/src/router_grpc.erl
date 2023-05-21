-module(router_grpc).

-include("router_grpc.hrl").
-include("router_grpc_service_registry.hrl").
-include_lib("router_log/include/router_log.hrl").

-export([unpack_data/2, pack_data/2]).



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



%% Interface



-spec unpack_data(
  Data :: binary(),
  Definition :: definition()
) ->
  typr:generic_return(
    OkRet :: {Pdu :: term(), Rest :: binary()},
    ErrorRet :: invalid_payload | unimplemented_compression
  ) | {more, Data :: binary()}.

unpack_data(?incomplete_data(Compression, Len, Data) = Packet, _Definition)
when (1 == Compression orelse 0 == Compression) andalso byte_size(Data) < Len ->
  {more, Packet};

unpack_data(?compressed_data(Len, _Data, _Rest), _Definition) ->
  {error, unimplemented_compression};

unpack_data(
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

unpack_data(_Packet, _Definition) ->
  {error, invalid_payload}.



-spec pack_data(
  Pdu :: term(),
  Definition :: definition()
) ->
  typr:generic_return(
    OkRet :: binary(),
    ErrorRet :: term()
  ).

pack_data(Pdu, #router_grpc_service_registry_definition_internal{definition = Definition, output = Output}) ->
  try Definition:encode_msg(Pdu, Output) of
    Data ->
      Len = byte_size(Data),
      {ok, ?uncompressed_data(Len, Data, <<>>)}
  catch error:Reason ->
    {error, Reason}
  end.
