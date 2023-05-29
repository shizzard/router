-module(router_grpc_client_pool_worker_sup).
-behaviour(supervisor).

-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_supervisor.hrl").
-include("router_grpc_service_registry.hrl").
-include("router_grpc_client_pool.hrl").

-export([pid/1, start_worker/1, stop_worker/2]).
-export([start_link/2, init/1]).



%% Interface



-spec pid(Definition :: router_grpc:definition_external()) ->
  Ret :: pid() | undefined.

pid(Definition) ->
  gproc:where({n, l, ?router_grpc_client_pool_gproc_key(?MODULE, Definition)}).



-spec start_worker(Definition :: router_grpc:definition_external()) ->
  typr:ok_return(OkRet :: pid()).

start_worker(Definition) ->
  supervisor:start_child(pid(Definition), [Definition]).



-spec stop_worker(
  Definition :: router_grpc:definition_external(),
  Pid :: erlang:pid()
) ->
  typr:generic_return(ErrorRet :: not_found).

stop_worker(Definition, Pid) ->
  supervisor:terminate_child(pid(Definition), Pid).



-spec start_link(
  Definition :: router_grpc:definition_external(),
  WorkerModule :: atom()
) ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: {already_started, pid()} | {shutdown, term()} | term()
  ).

start_link(Definition, WorkerModule) ->
  supervisor:start_link(?MODULE, {Definition, WorkerModule}).



init({Definition, WorkerModule}) ->
  router_log:component(router_grpc_client),
  true = gproc:reg({n, l, ?router_grpc_client_pool_gproc_key(?MODULE, Definition)}),
  ok = init_prometheus_metrics(),
  SupFlags = #{strategy => simple_one_for_one, intensity => 10, period => 10},
  Children = [
    #{
      id => ignored,
      start => {WorkerModule, start_link, []},
      restart => transient,
      shutdown => 5000,
      type => supervisor
    }
  ],
  {ok, {SupFlags, Children}}.



%% Internals



init_prometheus_metrics() ->
  ok.
