-module(echo_grpc_handler_room).

-include_lib("echo_grpc/include/echo_grpc.hrl").
-include_lib("echo/include/room_definitions.hrl").
-include_lib("echo_log/include/echo_log.hrl").

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
  Pdu :: lobby_definitions:'lg.service.demo.echo.GetStatsRq'(),
  S0 :: state()
) ->
  {ok, echo_grpc_h:handler_ret_ok_reply_fin(PduT :: lobby_definitions:'lg.service.demo.echo.GetStatsRs'()), S1 :: state()} |
  {error, echo_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

get_stats(#'lg.service.demo.echo.GetStatsRq'{name = Name}, S0) ->
  case Name of
    <<>> ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, #{}}, S0};
    _ ->
      get_stats_impl(Name, S0)
  end.



%%



get_stats_impl(Name, S0) ->
  case echo_room:get_stats(Name) of
    {ok, #{participants_n := N}} ->
      {ok, {reply_fin, #'lg.service.demo.echo.GetStatsRs'{
        participants_n = N
      }}, S0};
    {error, invalid_room} ->
      {error, {grpc_error, ?grpc_code_not_found, ?grpc_message_not_found, #{}}, S0}
  end.
