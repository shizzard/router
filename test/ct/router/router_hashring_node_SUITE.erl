-module(router_hashring_node_SUITE).
-compile([export_all, nowarn_export_all, nowarn_unused_function, nowarn_missing_spec]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("typr/include/typr_specs_eunit.hrl").
-include_lib("typr/include/typr_specs_ct.hrl").
-include_lib("router_grpc/include/router_grpc_service_registry.hrl").

-define(service_package, <<"lg.test.package">>).
-define(service_name, <<"StatefulService">>).
-define(service_fq_name, <<"lg.test.package.StatefulService">>).
-define(service_method_1, <<"MethodOne">>).
-define(service_method_2, <<"MethodTwo">>).
-define(service_method_3, <<"MethodThree">>).
-define(service_cmp_preemptive, 'PREEMPTIVE').
-define(service_cmp_blocking, 'BLOCKING').
-define(service_methods, [?service_method_1, ?service_method_2, ?service_method_3]).
-define(service_host, <<"test.lg">>).
-define(service_port, 8137).

-define(definition_preemptive, #router_grpc_service_registry_definition_external{
  id = {stateful, ?service_fq_name, ?service_host, ?service_port}, type = stateful,
  package = ?service_package, service_name = ?service_name, fq_service_name = ?service_fq_name, methods = ?service_methods,
  cmp = ?service_cmp_preemptive, host = ?service_host, port = ?service_port
}).
-define(definition_blocking, #router_grpc_service_registry_definition_external{
  id = {stateful, ?service_fq_name, ?service_host, ?service_port}, type = stateful,
  package = ?service_package, service_name = ?service_name, fq_service_name = ?service_fq_name, methods = ?service_methods,
  cmp = ?service_cmp_blocking, host = ?service_host, port = ?service_port
}).

-define(msg_conflict(FqServiceName, AgentId, AgentInstance), {msg_conflict, FqServiceName, AgentId, AgentInstance}).
-define(conflict_fun(),
  fun(StreamPid_, FqServiceName_, AgentId_, AgentInstance_) ->
    StreamPid_ ! ?msg_conflict(FqServiceName_, AgentId_, AgentInstance_),
    ok
  end
).

-define(rcv_timeout, 300).
-define(gen_cast(Msg), {'$gen_cast', Msg}).



all() -> [
  {group, g_register},
  {group, g_lookup},
  {group, g_unregister},
  {group, g_stream_terminate}
].

groups() -> [
  {g_register, [sequential], [
    g_register_noconflict, g_register_conflict_preemptive, g_register_conflict_blocking
  ]},
  {g_lookup, [sequential], [
    g_lookup_preemptive, g_lookup_blocking, g_lookup_nonexistent, g_lookup_bare
  ]},
  {g_unregister, [sequential], [
    g_unregister_preemptive, g_unregister_blocking
  ]},
  {g_stream_terminate, [sequential], [
    g_stream_terminate_preemptive, g_stream_terminate_blocking
  ]}
].

init_per_suite(Config) ->
  io:format("~p~n", [application:which_applications()]),
  AppsState = router_common_test_helper:init_applications_state(),
  ok = application:set_env(router, hashring, [{buckets_po2, 2}, {nodes_po2, 1}], [{persistent, true}]),
  {ok, _} = application:ensure_all_started(router),
  [{apps_state, AppsState} | Config].

init_per_group(_Name, Config) ->
  Config.

init_per_testcase(_Name, Config) ->
  erlang:process_flag(trap_exit, true),
  Config.

end_per_testcase(_Name, _Config) ->
  ok.

end_per_group(_Name, _Config) ->
  ok.

end_per_suite(Config) ->
  router_common_test_helper:rollback_applications_state(?config(apps_state, Config)),
  ok.



await_stopped(App) ->
  Apps = application:which_applications(),
  case lists:any(fun({App_, _, _}) when App_ == App -> true; (_) -> false end, Apps) of
    true ->
      io:format("waiting~n"),
      await_stopped(App);
    false ->
      ok
  end.



%% Group g_register



g_register_noconflict(_Config) ->
  Agent1 = <<"agent-1">>,
  Agent2 = <<"agent-2">>,
  Instance1 = <<"instance-0x00">>,
  Instance2 = <<"instance-0x01">>,
  %% Can register several non-conflicting agents on the node-bucket pair
  ok = router_hashring_node:register_agent(?definition_preemptive, Agent1, Instance1, ?conflict_fun()),
  ok = router_hashring_node:register_agent(?definition_preemptive, Agent2, Instance1, ?conflict_fun()),
  ok = router_hashring_node:register_agent(?definition_preemptive, Agent1, Instance2, ?conflict_fun()),
  ok = router_hashring_node:register_agent(?definition_preemptive, Agent2, Instance2, ?conflict_fun()),
  ok.



g_register_conflict_preemptive(_Config) ->
  Agent1 = <<"agent-1">>,
  Instance1 = <<"instance-0x00">>,
  ok = router_hashring_node:register_agent(?definition_preemptive, Agent1, Instance1, ?conflict_fun()),
  ok = router_hashring_node:register_agent(?definition_preemptive, Agent1, Instance1, ?conflict_fun()),
  assertConflict(?service_fq_name, Agent1, Instance1),
  ok.



g_register_conflict_blocking(_Config) ->
  Agent1 = <<"agent-1">>,
  Instance1 = <<"instance-0x00">>,
  ok = router_hashring_node:register_agent(?definition_blocking, Agent1, Instance1, ?conflict_fun()),
  {error, conflict} = router_hashring_node:register_agent(?definition_blocking, Agent1, Instance1, ?conflict_fun()),
  ok.



%% Group g_lookup



g_lookup_preemptive(_Config) ->
  Agent1 = <<"agent-1">>,
  Instance1 = <<"instance-0x00">>,
  ok = router_hashring_node:register_agent(?definition_preemptive, Agent1, Instance1, ?conflict_fun()),
  {ok, ?definition_preemptive} = router_hashring_node:lookup_agent(?service_fq_name, Agent1, Instance1),
  ok.



g_lookup_blocking(_Config) ->
  Agent1 = <<"agent-1">>,
  Instance1 = <<"instance-0x00">>,
  ok = router_hashring_node:register_agent(?definition_blocking, Agent1, Instance1, ?conflict_fun()),
  {ok, ?definition_blocking} = router_hashring_node:lookup_agent(?service_fq_name, Agent1, Instance1),
  ok.



g_lookup_nonexistent(_Config) ->
  Agent1 = <<"agent-1">>,
  Instance1 = <<"instance-0x00">>,
  {error, undefined} = router_hashring_node:lookup_agent(?service_fq_name, Agent1, Instance1),
  ok.



g_lookup_bare(_Config) ->
  Agent1 = <<"agent-1">>,
  Instance1 = <<"instance-0x00">>,
  Instance2 = <<"instance-0x01">>,
  ok = router_hashring_node:register_agent(?definition_preemptive, Agent1, Instance1, ?conflict_fun()),
  ok = router_hashring_node:register_agent(?definition_preemptive, Agent1, Instance2, ?conflict_fun()),
  {ok, List} = router_hashring_node:lookup_agent(?service_fq_name, Agent1),
  ?assertEqual(2, length(List)),
  ?definition_preemptive = proplists:get_value(Instance1, List),
  ?definition_preemptive = proplists:get_value(Instance2, List),
  ok.



%% Group g_unregister



g_unregister_preemptive(_Config) ->
  Agent1 = <<"agent-1">>,
  Instance1 = <<"instance-0x00">>,
  ok = router_hashring_node:register_agent(?definition_preemptive, Agent1, Instance1, ?conflict_fun()),
  ok = router_hashring_node:unregister_agent(?service_fq_name, Agent1, Instance1),
  ok.



g_unregister_blocking(_Config) ->
  Agent1 = <<"agent-1">>,
  Instance1 = <<"instance-0x00">>,
  ok = router_hashring_node:register_agent(?definition_blocking, Agent1, Instance1, ?conflict_fun()),
  ok = router_hashring_node:unregister_agent(?service_fq_name, Agent1, Instance1),
  ok.



%% Group g_stream_terminate



g_stream_terminate_preemptive(_Config) ->
  Agent1 = <<"agent-1">>,
  Instance1 = <<"instance-0x00">>,
  Mock = stream_h_mock(?definition_preemptive, Agent1, Instance1, ?conflict_fun()),
  {ok, ?definition_preemptive} = router_hashring_node:lookup_agent(?service_fq_name, Agent1, Instance1),
  ok = stream_h_mock_kill(Mock),
  {error, undefined} = router_hashring_node:lookup_agent(?service_fq_name, Agent1, Instance1),
  ok.



g_stream_terminate_blocking(_Config) ->
  Agent1 = <<"agent-1">>,
  Instance1 = <<"instance-0x00">>,
  Mock = stream_h_mock(?definition_blocking, Agent1, Instance1, ?conflict_fun()),
  {ok, ?definition_blocking} = router_hashring_node:lookup_agent(?service_fq_name, Agent1, Instance1),
  ok = stream_h_mock_kill(Mock),
  {error, undefined} = router_hashring_node:lookup_agent(?service_fq_name, Agent1, Instance1),
  ok.



%% Internals



stream_h_mock(Definition, AgentId, AgentInstance, ConflictFun) ->
  Self = self(),
  Pid = spawn(fun() ->
    ok = router_hashring_node:register_agent(Definition, AgentId, AgentInstance, ConflictFun),
    Self ! registered,
    stream_h_mock_loop_forever()
  end),
  MonRef = erlang:monitor(process, Pid),
  receive
    registered -> ok
  after
    ?rcv_timeout -> error(didnt_get_registration_confirmation)
  end,
  {Pid, MonRef}.



stream_h_mock_loop_forever() ->
  timer:sleep(1000),
  stream_h_mock_loop_forever().



stream_h_mock_kill({Pid, MonRef}) ->
  erlang:exit(Pid, kill),
  receive
    {'DOWN', MonRef, process, Pid, killed} -> ok
  after
    ?rcv_timeout -> error(didnt_get_stream_mock_killed)
  end.



assertConflict(FqServiceName, AgentId, AgentInstance) ->
  receive
    ?msg_conflict(FqServiceName, AgentId, AgentInstance) -> ok
  after
    ?rcv_timeout -> error(didnt_get_conflict)
  end.
