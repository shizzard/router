-module(router_grpc_client_pool_master_sup).
-behaviour(supervisor).

-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_supervisor.hrl").

-export([start_pool/1, start_pool/2, start_pool/3, stop_pool/1]).
-export([start_link/0, init/1]).



%% Interface



-spec start_pool(Definition :: router_grpc:definition_external()) ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: already_started
  ).

start_pool(Definition) ->
  start_pool(Definition, router_grpc_client).



-spec start_pool(
  Definition :: router_grpc:definition_external(),
  WorkerModule :: atom()
) ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: already_started
  ).

start_pool(Definition, WorkerModule) ->
  {ok, WorkersN} = router_config:get(router_grpc, [client, pool_size]),
  start_pool(Definition, WorkerModule, WorkersN).



-spec start_pool(
  Definition :: router_grpc:definition_external(),
  WorkerModule :: atom(),
  WorkersN :: pos_integer()
) ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: already_started
  ).

start_pool(Definition, WorkerModule, WorkersN) ->
  case router_grpc_client_pool_sup:pid(Definition) of
    undefined ->
      supervisor:start_child(?MODULE, [Definition, WorkerModule, WorkersN]);
    _Pid ->
      {error, already_started}
  end.



-spec stop_pool(Definition :: router_grpc:definition_external()) ->
  typr:generic_return(ErrorRet :: not_found).

stop_pool(Definition) ->
  supervisor:terminate_child(?MODULE, router_grpc_client_pool_sup:pid(Definition)).



-spec start_link() ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: {already_started, pid()} | {shutdown, term()} | term()
  ).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).



init([]) ->
  router_log:component(router_grpc_client),
  ok = init_prometheus_metrics(),
  SupFlags = #{strategy => simple_one_for_one, intensity => 10, period => 10},
  Children = [
    #{
      id => ignored,
      start => {router_grpc_client_pool_sup, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => supervisor
    }
  ],
  {ok, {SupFlags, Children}}.



%% Internals



init_prometheus_metrics() ->
  ok.
