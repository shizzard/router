-module(router_grpc_client_pool_SUITE).
-compile([export_all, nowarn_export_all, nowarn_unused_function, nowarn_missing_spec]).

-include_lib("router_log/include/router_log.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("typr/include/typr_specs_eunit.hrl").
-include_lib("typr/include/typr_specs_ct.hrl").
-include_lib("router_grpc/include/router_grpc_service_registry.hrl").

-define(port, 8137).
-define(definition, #router_grpc_service_registry_definition_external{
  id = {stateful, <<"lg.test.StatefulService">>, <<"localhost">>, ?port},
  type = stateful,
  package = <<"lg.test">>,
  service_name = <<"StatefulService">>,
  fq_service_name = <<"lg.test.StatefulService">>,
  methods = [<<"MethodOne">>],
  cmp = 'PREEMPTIVE',
  host = <<"localhost">>,
  port = ?port
}).
-define(client, router_grpc_client_pool_SUITE_client).
-define(workers_n, 10).
-define(rcv_timeout, 300).

all() -> [
  {group, g_client_pool_master_sup},
  {group, g_client_pool}
].

groups() -> [
  {g_client_pool_master_sup, [sequential], [
    g_client_pool_master_sup_start_pool, g_client_pool_master_sup_stop_pool,
    g_client_pool_master_sup_already_started_pool
  ]},
  {g_client_pool, [sequential], [
    g_client_pool_spawn_workers, g_client_pool_despawn_workers, g_client_pool_over_despawn_workers,
    g_client_pool_get_workers
  ]}
].

init_per_suite(Config) ->
  AppsState = router_common_test_helper:init_applications_state(),
  ok = application:set_env(router_grpc, listener, [{port, ?port}], [{persistent, true}]),
  ok = application:set_env(router_grpc, client, [{pool_size, 10}], [{persistent, true}]),
  ok = application:set_env(router_grpc, session, [{inactivity_limit_ms, 15000}], [{persistent, true}]),
  ok = application:set_env(router, hashring, [{buckets_po2, 2}, {nodes_po2, 1}], [{persistent, true}]),
  {ok, _} = application:ensure_all_started(router_grpc),
  [{apps_state, AppsState} | Config].

init_per_group(_Name, Config) ->
  Config.

init_per_testcase(_Name, Config) ->
  %% Need this to ensure master pool supervisor has no children
  %% Just killing the supervisor might exceed the restart intencity of the
  %% application root supervisor
  ok = application:stop(router_grpc),
  ok = application:start(router_grpc),
  Config.

end_per_testcase(_Name, _Config) ->
  ok.

end_per_group(_Name, _Config) ->
  ok.

end_per_suite(Config) ->
  router_common_test_helper:rollback_applications_state(?config(apps_state, Config)),
  ok.



%% Group g_client_pool_master_sup



g_client_pool_master_sup_start_pool(_Config) ->
  {ok, _} = router_grpc_client_pool_master_sup:start_pool(?definition, ?client, ?workers_n),
  ?assertNotEqual(undefined, router_grpc_client_pool_sup:pid(?definition)),
  ?assertNotEqual(undefined, router_grpc_client_pool_worker_sup:pid(?definition)),
  ?assertNotEqual(undefined, router_grpc_client_pool:pid(?definition)),
  ?assertEqual(?workers_n, length(unpack(router_grpc_client_pool:get_workers(?definition)))),
  ?assertEqual(?workers_n, length(supervisor:which_children(router_grpc_client_pool_worker_sup:pid(?definition)))).



g_client_pool_master_sup_stop_pool(_Config) ->
  {ok, _} = router_grpc_client_pool_master_sup:start_pool(?definition, ?client, ?workers_n),
  ok = router_grpc_client_pool_master_sup:stop_pool(?definition),
  ?assertEqual(undefined, router_grpc_client_pool_sup:pid(?definition)),
  ?assertEqual(undefined, router_grpc_client_pool_worker_sup:pid(?definition)),
  ?assertEqual(undefined, router_grpc_client_pool:pid(?definition)).



g_client_pool_master_sup_already_started_pool(_Config) ->
  {ok, _} = router_grpc_client_pool_master_sup:start_pool(?definition, ?client, ?workers_n),
  {error, already_started} = router_grpc_client_pool_master_sup:start_pool(?definition, ?client, ?workers_n).



%% Group g_client_pool



g_client_pool_spawn_workers(_Config) ->
  {ok, _} = router_grpc_client_pool_master_sup:start_pool(?definition, ?client, ?workers_n),
  ?assertEqual(?workers_n, length(unpack(router_grpc_client_pool:get_workers(?definition)))),
  ?assertEqual(?workers_n, length(supervisor:which_children(router_grpc_client_pool_worker_sup:pid(?definition)))),
  ok = router_grpc_client_pool:spawn_workers(?definition, 4),
  ?assertEqual(?workers_n + 4, length(unpack(router_grpc_client_pool:get_workers(?definition)))),
  ?assertEqual(?workers_n + 4, length(supervisor:which_children(router_grpc_client_pool_worker_sup:pid(?definition)))).



g_client_pool_despawn_workers(_Config) ->
  {ok, _} = router_grpc_client_pool_master_sup:start_pool(?definition, ?client, ?workers_n),
  ?assertEqual(?workers_n, length(unpack(router_grpc_client_pool:get_workers(?definition)))),
  ?assertEqual(?workers_n, length(supervisor:which_children(router_grpc_client_pool_worker_sup:pid(?definition)))),
  ok = router_grpc_client_pool:despawn_workers(?definition, 4),
  ?assertEqual(?workers_n - 4, length(unpack(router_grpc_client_pool:get_workers(?definition)))),
  ?assertEqual(?workers_n - 4, length(supervisor:which_children(router_grpc_client_pool_worker_sup:pid(?definition)))).



g_client_pool_over_despawn_workers(_Config) ->
  {ok, _} = router_grpc_client_pool_master_sup:start_pool(?definition, ?client, ?workers_n),
  ?assertEqual(?workers_n, length(unpack(router_grpc_client_pool:get_workers(?definition)))),
  ?assertEqual(?workers_n, length(supervisor:which_children(router_grpc_client_pool_worker_sup:pid(?definition)))),
  ok = router_grpc_client_pool:despawn_workers(?definition, ?workers_n + 4),
  ?assertEqual(0, length(unpack(router_grpc_client_pool:get_workers(?definition)))),
  ?assertEqual(0, length(supervisor:which_children(router_grpc_client_pool_worker_sup:pid(?definition)))).

g_client_pool_get_workers(_Config) ->
  {ok, _} = router_grpc_client_pool_master_sup:start_pool(?definition, ?client, ?workers_n),
  {ok, Workers} = router_grpc_client_pool:get_workers(?definition),
  ?assertEqual(?workers_n, length(Workers)),
  ?assert(lists:member(unpack(router_grpc_client_pool:get_random_worker(?definition)), Workers)),
  ?assert(lists:member(unpack(router_grpc_client_pool:get_random_worker(?definition)), Workers)),
  ?assert(lists:member(unpack(router_grpc_client_pool:get_random_worker(?definition)), Workers)).



%% Helpers



unpack({ok, V}) -> V.
