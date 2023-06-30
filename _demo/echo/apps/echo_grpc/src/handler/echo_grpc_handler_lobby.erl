-module(echo_grpc_handler_lobby).

-include_lib("echo_grpc/include/echo_grpc.hrl").
-include_lib("echo/include/lobby_definitions.hrl").
-include_lib("echo/include/gateway_definitions.hrl").
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
  spawn_room_impl_spawn_client(Name, S0).

spawn_room_impl_spawn_client(Name, S0) ->
  {ok, Client} = echo_grpc_client_unary:start_link(),
  spawn_room_impl_send_request(Name, Client, S0).

spawn_room_impl_send_request(Name, Client, S0) ->
  {ok, RanchPort} = echo_config:get(echo, [room, listener, port]),
  Pdu = #'lg.service.demo.rtgw.SpawnTunnelRq'{
    endpoint = #'lg.core.network.Endpoint'{host = <<"localhost">>, port = RanchPort},
    name = Name
  },
  case echo_grpc_client_unary:request(
    Client, <<"lg.service.demo.rtgw.GatewayService">>, <<"SpawnTunnel">>, #{}, gateway_definitions, Pdu, 'lg.service.demo.rtgw.SpawnTunnelRs'
  ) of
    {ok, {Status, Headers, undefined, undefined}} ->
      ?l_debug(#{text => "Failed to create tunnel", result => error, details => #{
        status => Status, headers => Headers
      }}),
      {error, {grpc_error, ?grpc_code_internal, ?grpc_message_internal, #{}}, S0};
    {ok, {_Status, _Headers, #'lg.service.demo.rtgw.SpawnTunnelRs'{
      endpoint = #'lg.core.network.Endpoint'{host = RtgwHost, port = RtgwPort},
      name = Name,
      secret = Secret
    }, _Trailers}} ->
      spawn_room_impl_reply(Name, Secret, RtgwHost, RtgwPort, S0)
  end.

spawn_room_impl_reply(Name, Secret, RtgwHost, RtgwPort, S0) ->
  case echo_room_sup:start_room(Name, Secret) of
    {ok, _Pid} ->
      {ok, {reply_fin, #'lg.service.demo.echo.SpawnRoomRs'{
        endpoint = #'lg.core.network.Endpoint'{
          host = RtgwHost,
          port = RtgwPort
        },
        name = Name,
        secret = Secret
      }}, S0};
    {error, Reason} ->
      ?l_debug(#{text => "Failed to create room", result => error, details => #{reason => Reason}}),
      {error, {grpc_error, ?grpc_code_internal, ?grpc_message_internal, #{}}, S0}
  end.
