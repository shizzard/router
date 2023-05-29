-module(router_grpc_stream_sup).
-behaviour(supervisor).

-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_supervisor.hrl").

-export([start_handler/4, lookup_handler/1, recover_handler/2, start_link/0, init/1]).



%% Interface



-spec start_handler(
  SessionId :: router_grpc_stream_h:session_id(),
  DefinitionInternal :: router_grpc:definition_internal(),
  DefinitionExternal :: router_grpc:definition_external(),
  ConnReq :: cowboy_req:req()
) ->
  typr:ok_return(OkRet :: pid()).

start_handler(SessionId, DefinitionInternal, DefinitionExternal, ConnReq) ->
  supervisor:start_child(?MODULE, [SessionId, DefinitionInternal, DefinitionExternal, ConnReq, self()]).



-spec lookup_handler(SessionId :: router_grpc_stream_h:session_id()) ->
  typr:generic_return(OkRet :: pid(), ErrorRet :: undefined).

lookup_handler(SessionId) ->
  case router_grpc_stream_h:lookup(SessionId) of
    undefined -> {error, undefined};
    Pid -> {ok, Pid}
  end.



-spec recover_handler(
  Pid :: pid(),
  SessionId :: router_grpc_stream_h:session_id()
) ->
  typr:generic_return(ErrorRet :: conn_alive).

recover_handler(Pid, SessionId) ->
  router_grpc_stream_h:recover(Pid, SessionId, self()).



-spec start_link() ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: {already_started, pid()} | {shutdown, term()} | term()
  ).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).



init([]) ->
  router_log:component(router_grpc_stream),

  ok = init_prometheus_metrics(),

  SupFlags = #{strategy => simple_one_for_one, intensity => 10, period => 10},
  Children = [
    #{
      id => ignored,
      start => {router_grpc_stream_h, start_link, []},
      restart => temporary,
      shutdown => 5000,
      type => worker
    }
  ],
  {ok, {SupFlags, Children}}.



%% Internals



init_prometheus_metrics() ->
  % prometheus_summary:declare([
  %   {name, ?metric_smr_foo},
  %   {labels, [a, b]},
  %   {help, "Help"}
  % ]),
  % prometheus_histogram:new([
  %   {name, ?metric_hgr_foo},
  %   {labels, [a, b]},
  %   {buckets, [1 * trunc(math:pow(2, E)) || E <- lists:seq(0, 7)]},
  %   {help, "Help"}
  % ]),
  % prometheus_counter:new([
  %   {name, ?metric_cnt_foo},
  %   {labels, [a, b]},
  %   {help, "Help"}
  % ]).
  ok.
