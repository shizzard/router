-module('router_grpc_client_pool_sup').
-behaviour(supervisor).

-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_supervisor.hrl").
-include("router_grpc_service_registry.hrl").
-include("router_grpc_client_pool.hrl").

-export([pid/1]).
-export([start_link/3, init/1]).



%% Interface



-spec pid(Definition :: router_grpc:definition_external()) ->
  Ret :: pid() | undefined.

pid(Definition) ->
  gproc:where({n, l, ?router_grpc_client_pool_gproc_key(?MODULE, Definition)}).



-spec start_link(
  Definition :: router_grpc:definition_external(),
  WorkerModule :: atom(),
  WorkersN :: pos_integer()
) ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: {already_started, pid()} | {shutdown, term()} | term()
  ).

start_link(Definition, WorkerModule, WorkersN) ->
  supervisor:start_link(?MODULE, {Definition, WorkerModule, WorkersN}).



init({Definition, WorkerModule, WorkersN}) ->
  router_log:component(router_grpc_client),
  true = gproc:reg({n, l, ?router_grpc_client_pool_gproc_key(?MODULE, Definition)}),
  ok = init_prometheus_metrics(),
  SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
  Children = [
    #{
      id => router_grpc_client_pool_worker_sup,
      start => {router_grpc_client_pool_worker_sup, start_link, [Definition, WorkerModule]},
      restart => permanent,
      shutdown => 5000,
      type => supervisor
    },
    #{
      id => router_grpc_client_pool,
      start => {router_grpc_client_pool, start_link, [Definition, WorkersN]},
      restart => permanent,
      shutdown => 5000,
      type => worker
    }
  ],
  {ok, {SupFlags, Children}}.



%% Internals



init_prometheus_metrics() ->
  ok.
