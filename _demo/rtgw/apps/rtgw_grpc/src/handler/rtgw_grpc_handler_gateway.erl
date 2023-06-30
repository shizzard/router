-module(rtgw_grpc_handler_gateway).

-include_lib("rtgw_grpc/include/rtgw_grpc.hrl").
-include_lib("rtgw/include/gateway_definitions.hrl").
-include_lib("rtgw_log/include/rtgw_log.hrl").

-export([init/2]).
-export([spawn_tunnel/2]).

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



-spec spawn_tunnel(
  Pdu :: lobby_definitions:'lg.service.demo.rtgw.SpawnRoomRq'(),
  S0 :: state()
) ->
  {ok, rtgw_grpc_h:handler_ret_ok_reply_fin(PduT :: lobby_definitions:'lg.service.demo.rtgw.SpawnRoomRs'()), S1 :: state()} |
  {error, rtgw_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

spawn_tunnel(#'lg.service.demo.rtgw.SpawnTunnelRq'{
  name = Name,
  endpoint = #'lg.core.network.Endpoint'{
    host = Host, port = Port
  }
}, S0) ->
  case Name of
    <<>> ->
      ?l_debug(#{text => "Invalid tunnel name: empty", result => error}),
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, #{}}, S0};
    _ ->
      spawn_tunnel_impl(Name, Host, Port, S0)
  end.



%%



spawn_tunnel_impl(Name, Host, Port, S0) ->
  Secret = secret(),
  {ok, RanchPort} = rtgw_config:get(rtgw, [tunnel, listener, port]),
  case rtgw_tunnel_registry:create(Name, Secret, Host, Port) of
    ok ->
      ok = rtgw_grpc_client_control_stream:register_agent(Name, Name),
      {ok, {reply_fin, #'lg.service.demo.rtgw.SpawnTunnelRs'{
        endpoint = #'lg.core.network.Endpoint'{
          host = <<"localhost">>,
          port = RanchPort
        },
        name = Name,
        secret = Secret
      }}, S0};
    {error, Reason} ->
      ?l_debug(#{text => "Failed to create tunnel", result => error, details => #{reason => Reason}}),
      {error, {grpc_error, ?grpc_code_internal, ?grpc_message_internal, #{}}, S0}
  end.



secret() ->
  Characters = lists:seq(48, 57) ++ lists:seq(65, 90),
  list_to_binary([lists:nth(rand:uniform(length(Characters) - 1), Characters) || _ <- lists:seq(1, 10)]).
