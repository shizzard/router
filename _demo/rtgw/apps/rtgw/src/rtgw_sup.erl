-module('rtgw_sup').
-behaviour(supervisor).

-include_lib("typr/include/typr_specs_supervisor.hrl").

-export([start_link/0, init/1]).



%% Interface



-spec start_link() ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: {already_started, pid()} | {shutdown, term()} | term()
  ).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).



init([]) ->
  rtgw_log:component(rtgw),
  ok = init_prometheus_metrics(),
  {ok, RanchPort} = rtgw_config:get(rtgw, [tunnel, listener, port]),
  SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
  Children = [
    #{
      id => rtgw_tunnel_registry,
      start => {rtgw_tunnel_registry, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    },
    ranch:child_spec(
      rtgw_listener, ranch_tcp,
      #{socket_opts => [{port, RanchPort}], max_connections => 100},
      rtgw_tunnel_protocol,
      []
    )
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
