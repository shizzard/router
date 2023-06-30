-module(rtgw_grpc_handler_tunnel).

-include_lib("rtgw/include/rtgw_tunnel.hrl").
-include_lib("rtgw_grpc/include/rtgw_grpc.hrl").
-include_lib("rtgw/include/tunnel_definitions.hrl").
-include_lib("rtgw_log/include/rtgw_log.hrl").

-export([init/2]).
-export([get_stats/2]).

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



-spec get_stats(
  Pdu :: lobby_definitions:'lg.service.demo.rtgw.GetStatsRq'(),
  S0 :: state()
) ->
  {ok, rtgw_grpc_h:handler_ret_ok_reply_fin(PduT :: lobby_definitions:'lg.service.demo.rtgw.GetStatsRs'()), S1 :: state()} |
  {error, rtgw_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

get_stats(#'lg.service.demo.rtgw.GetStatsRq'{name = Name}, S0) ->
  case Name of
    <<>> ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, #{}}, S0};
    _ ->
      get_stats_impl(Name, S0)
  end.



%%



get_stats_impl(Name, S0) ->
  case rtgw_tunnel_registry:lookup(Name) of
    {ok, #tunnel{traffic_in_bytes = In, traffic_out_bytes = Out}} ->
      {ok, {reply_fin, #'lg.service.demo.rtgw.GetStatsRs'{
        traffic_in_bytes = In,
        traffic_out_bytes = Out
      }}, S0};
    {error, not_found} ->
      {error, {grpc_error, ?grpc_code_not_found, ?grpc_message_not_found, #{}}, S0}
  end.
