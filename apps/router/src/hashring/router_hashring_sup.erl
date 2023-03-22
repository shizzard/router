-module('router_hashring_sup').
-behaviour(supervisor).

-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_supervisor.hrl").

-export([start_link/1, init/1]).



%% Interface



-spec start_link({
  BucketsPO2 :: router_hasring_po2:hr_buckets_po2(),
  NodesPO2 :: router_hasring_po2:hr_nodes_po2()
}) ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: {already_started, pid()} | {shutdown, term()} | term()
  ).

start_link({BucketsPO2, NodesPO2}) ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, {BucketsPO2, NodesPO2}).



init({BucketsPO2, NodesPO2}) ->
  router_log:component(router_hashring),

  router_hashring:init(BucketsPO2, NodesPO2),
  {ok, HR} = router_hashring:get(),

  ok = init_prometheus_metrics(),
  SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
  NodeSpec = #{
    id => router_hashring_node, start => {router_hashring_node, start_link, []},
    restart => permanent, shutdown => 10000, type => worker
  },
  Children = router_hashring_po2:child_specs(HR, NodeSpec, #{id_fun => fun router_hashring:node_name/1}),
  ?l_info(#{text => "Hashring nodes to be started", what => init, details => #{count => length(Children)}}),
  {ok, {SupFlags, Children}}.



%% Internals



init_prometheus_metrics() ->
  ok.
