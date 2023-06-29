-module(echo_grpc).

-include_lib("echo_grpc/include/echo_grpc.hrl").
-include_lib("echo_log/include/echo_log.hrl").

-export([unpack_decode_pdu/3, encode_pack_pdu/3]).
-export([unpack_data/1, pack_data/1]).
-export([decode_pdu/3, encode_pdu/3]).
-export([fin_to_bool/1, bool_to_fin/1]).



%% Types



-type definition() :: atom().
-type msg_type() :: atom().



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
  Definition :: definition(),
  MsgType :: msg_type()
) ->
  typr:generic_return(
    OkRet :: {Pdu :: term(), Rest :: binary()},
    ErrorRet :: invalid_payload | unimplemented_compression
  ) | {more, Data :: binary()}.

unpack_decode_pdu(Data, Definition, MsgType) ->
  case unpack_data(Data) of
    {ok, {Data_, _Rest}} ->
      decode_pdu(Data_, Definition, MsgType);
    Etc ->
      Etc
  end.



-spec encode_pack_pdu(
  Pdu :: term(),
  Definition :: definition(),
  MsgType :: msg_type()
) ->
  typr:generic_return(
    OkRet :: binary(),
    ErrorRet :: term()
  ).

encode_pack_pdu(Pdu, Definition, MsgType) ->
  case encode_pdu(Pdu, Definition, MsgType) of
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
  Definition :: definition(),
  MsgType :: msg_type()
) ->
  typr:generic_return(
    OkRet :: {Pdu :: term(), Rest :: binary()},
    ErrorRet :: invalid_payload | unimplemented_compression
  ) | {more, Data :: binary()}.

decode_pdu(Data, Definition, MsgType) ->
  try Definition:decode_msg(Data, MsgType) of
    Pdu -> {ok, {Pdu, <<>>}}
  catch error:Reason ->
    ?l_debug(#{text => "gRPC payload decode error", what => data, result => error, details => #{
      definition => Definition, data => Data, reason => Reason
    }}),
    {error, invalid_payload}
  end.



-spec encode_pdu(
  Pdu :: term(),
  Definition :: definition(),
  MsgType :: msg_type()
) ->
  typr:generic_return(
    OkRet :: binary(),
    ErrorRet :: term()
  ).

encode_pdu(Pdu, Definition, MsgType) ->
  try Definition:encode_msg(Pdu, MsgType) of
    Data ->
      {ok, Data}
  catch error:Reason ->
    {error, Reason}
  end.



-spec fin_to_bool(Fin :: cowboy_stream:fin()) ->
  Ret :: boolean().

fin_to_bool(fin) -> true;
fin_to_bool(nofin) -> false;
fin_to_bool(Etc) -> error({invalid_fin, Etc}).



-spec bool_to_fin(IsFin :: boolean()) ->
  Ret :: cowboy_stream:fin().

bool_to_fin(true) -> fin;
bool_to_fin(false) -> nofin.
