-module(router_grpc_external_stream_sup).
-behaviour(supervisor).

-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_supervisor.hrl").

-export([start_handler/2, start_link/0, init/1]).



%% Interface



-spec start_handler(
  Definition :: router_grpc:definition_external(),
  Req :: cowboy_req:req()
) ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: no_workers_available
  ).

start_handler(Definition, Req) ->
  supervisor:start_child(?MODULE, [Definition, Req]).



-spec start_link() ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: {already_started, pid()} | {shutdown, term()} | term()
  ).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).



init([]) ->
  router_log:component(router_grpc_external),
  ok = init_prometheus_metrics(),
  SupFlags = #{strategy => simple_one_for_one, intensity => 10, period => 10},
  Children = [
    #{
      id => ignored,
      start => {router_grpc_external_stream_h, start_link, []},
      restart => temporary,
      shutdown => 5000,
      type => worker
    }
  ],
  {ok, {SupFlags, Children}}.



%% Internals



init_prometheus_metrics() ->
  ok.
