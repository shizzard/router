-module(echo_grpc_handler_lobby).

-include_lib("echo_grpc/include/echo_grpc.hrl").
-include_lib("echo/include/lobby_definitions.hrl").
-include_lib("echo_log/include/echo_log.hrl").

-export([init/2]).
-export([spawn_room/2]).

-record(state, {
  conn_req :: cowboy_req:req()
}).
-type state() :: #state{}.



%% Metrics



%% gRPC endpoints



-spec init(
  Function :: atom(),
  ConnReq :: cowboy_req:req()
) -> state().

init(_Function, ConnReq) ->
  #state{conn_req = ConnReq}.



-spec spawn_room(
  Pdu :: lobby_definitions:'lg.service.demo.echo.SpawnRoomRq'(),
  S0 :: state()
) ->
  {ok, echo_grpc_h:handler_ret_ok_reply_fin(PduT :: lobby_definitions:'lg.service.demo.echo.SpawnRoomRs'()), S1 :: state()} |
  {error, echo_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

spawn_room(#'lg.service.demo.echo.SpawnRoomRq'{name = Name}, S0) ->
  case Name of
    <<>> ->
      ?l_debug(#{text => "Invalid room name: empty", result => error}),
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, #{}}, S0};
    _ ->
      spawn_room_impl(Name, S0)
  end.



%%



spawn_room_impl(Name, S0) ->
  Secret = <<"secret">>,
  {ok, RanchPort} = echo_config:get(echo, [room, listener, port]),
  case echo_room_sup:start_room(Name, Secret) of
    {ok, _Pid} ->
      {ok, {reply_fin, #'lg.service.demo.echo.SpawnRoomRs'{
        endpoint = #'lg.core.network.Endpoint'{
          host = <<"localhost">>,
          port = RanchPort
        },
        name = Name,
        secret = Secret
      }}, S0};
    {error, Reason} ->
      ?l_debug(#{text => "Failed to create room", result => error, details => #{reason => Reason}}),
      {error, {grpc_error, ?grpc_code_internal, ?grpc_message_internal, #{}}, S0}
  end.
