-module('router_sup').
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
  router_log:component(router),

  {ok, BucketsPO2} = router_config:get(router, [hashring, buckets_po2]),
  {ok, NodesPO2} = router_config:get(router, [hashring, nodes_po2]),

  ok = init_prometheus_metrics(),
  SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
  Children = [#{
    id => router_hashring_sup,
    start => {router_hashring_sup, start_link, [{BucketsPO2, NodesPO2}]},
    restart => permanent,
    shutdown => infinity,
    type => supervisor
  }],
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
