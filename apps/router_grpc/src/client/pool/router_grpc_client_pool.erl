-module(router_grpc_client_pool).
-behaviour(gen_server).

-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").
-include_lib("router_pb/include/registry_definitions.hrl").
-include("router_grpc_service_registry.hrl").
-include("router_grpc_client_pool.hrl").

-export([pid/1, spawn_workers/2, despawn_workers/2, get_workers/1]).
-export([
  start_link/2, init/1,
  handle_continue/2, handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3
]).

-record(worker, {
  pid :: erlang:pid(),
  mon_ref :: erlang:reference()
}).

-record(state, {
  definition :: router_grpc:definition_external(),
  workers_n :: pos_integer(),
  workers = #{} :: #{erlang:reference() => #worker{}}
}).
-type state() :: #state{}.

%% Messages



-define(msg_init_workers(), {msg_init_workers}).
-define(msg_spawn_workers(WorkersN), {msg_spawn_workers, WorkersN}).
-define(msg_despawn_workers(WorkersN), {msg_despawn_workers, WorkersN}).
-define(msg_get_workers(), {msg_get_workers}).



%% Metrics



%% Interface



-spec pid(Definition :: router_grpc:definition_external()) ->
  Ret :: pid() | undefined.

pid(Definition) ->
  gproc:where({n, l, ?router_grpc_client_pool_gproc_key(?MODULE, Definition)}).



-spec spawn_workers(
  Definition :: router_grpc:definition_external(),
  WorkersN :: pos_integer()
) ->
  typr:ok_return().

spawn_workers(Definition, WorkersN) ->
  gen_server:call(pid(Definition), ?msg_spawn_workers(WorkersN)).



-spec despawn_workers(
  Definition :: router_grpc:definition_external(),
  WorkersN :: pos_integer()
) ->
  typr:ok_return().

despawn_workers(Definition, WorkersN) ->
  gen_server:call(pid(Definition), ?msg_despawn_workers(WorkersN)).



-spec get_workers(Definition :: router_grpc:definition_external()) ->
  typr:generic_return(
    OkRet :: [pid()],
    ErrorRet :: term()
  ).

get_workers(Definition) ->
  gen_server:call(pid(Definition), ?msg_get_workers()).



-spec start_link(
  Definition :: router_grpc:definition_external(),
  WorkersN :: pos_integer()
) ->
  typr:ok_return(OkRet :: pid()).

start_link(Definition, WorkersN) ->
  gen_server:start_link(?MODULE, {Definition, WorkersN}, []).



init({Definition, WorkersN}) ->
  router_log:component(router_grpc_client),
  true = gproc:reg({n, l, ?router_grpc_client_pool_gproc_key(?MODULE, Definition)}),
  ok = quickrand:seed(),
  ok = init_prometheus_metrics(),
  S0 = #state{definition = Definition, workers_n = WorkersN},
  {ok, S0, {continue, ?msg_init_workers()}}.



%% Handlers



-spec handle_continue(Msg :: term(), S0 :: state()) ->
  typr:gen_server_noreply(S1 :: state()) | typr:gen_server_stop_noreply(S1 :: state()).

handle_continue(?msg_init_workers(), #state{workers_n = WorkersN} = S0) ->
  {noreply, lists:foldl(fun(_N, SAcc) -> start_worker(SAcc) end, S0, lists:seq(1, WorkersN))};

handle_continue(Unexpected, S0) ->
  ?l_error(#{text => "Unexpected continue", what => handle_continue, details => Unexpected}),
  {noreply, S0}.



handle_call(?msg_spawn_workers(WorkersN), _GenReplyTo, S0) ->
  S1 = lists:foldl(fun(_N, SAcc) -> start_worker(SAcc) end, S0, lists:seq(1, WorkersN)),
  {reply, ok, S1};

handle_call(?msg_despawn_workers(WorkersN), _GenReplyTo, S0) ->
  S1 = lists:foldl(fun(_N, SAcc) -> stop_worker(SAcc) end, S0, lists:seq(1, WorkersN)),
  {reply, ok, S1};

handle_call(?msg_get_workers(), _GenReplyTo, #state{workers = Workers} = S0) ->
  {reply, {ok, maps:values(Workers)}, S0};

handle_call(Unexpected, _GenReplyTo, S0) ->
  ?l_error(#{text => "Unexpected call", what => handle_call, details => Unexpected}),
  {reply, badarg, S0}.



handle_cast(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected cast", what => handle_cast, details => Unexpected}),
  {noreply, S0}.



handle_info(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected info", what => handle_info, details => Unexpected}),
  {noreply, S0}.



terminate(_Reason, _S0) ->
  ok.



code_change(_OldVsn, S0, _Extra) ->
  {ok, S0}.



%% Internals



init_prometheus_metrics() ->
  ok.



start_worker(#state{definition = Definition, workers = Workers, workers_n = WorkersN} = S0) ->
  {ok, Pid} = router_grpc_client_pool_worker_sup:start_worker(Definition),
  Worker = #worker{pid = Pid, mon_ref = erlang:monitor(process, Pid)},
  S0#state{workers = Workers#{Worker#worker.mon_ref => Worker}, workers_n = WorkersN + 1}.



stop_worker(#state{workers = Workers} = S0) when map_size(Workers) == 0 ->
  S0;

stop_worker(#state{definition = Definition, workers = Workers, workers_n = WorkersN} = S0) ->
  %% Naive implementation here: stop first worker available
  [{_, #worker{mon_ref = MonRef, pid = Pid}} | _] = maps:to_list(Workers),
  erlang:demonitor(MonRef, [flush]),
  case router_grpc_client_pool_worker_sup:stop_worker(Definition, Pid) of
    ok ->
      S0#state{workers = maps:remove(MonRef, Workers), workers_n = WorkersN - 1};
    {error, not_found} ->
      stop_worker(S0#state{workers = maps:remove(MonRef, Workers), workers_n = WorkersN - 1})
  end.
