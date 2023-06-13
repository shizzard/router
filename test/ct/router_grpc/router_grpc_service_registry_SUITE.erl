-module(router_grpc_service_registry_SUITE).
-compile([export_all, nowarn_export_all, nowarn_unused_function, nowarn_missing_spec]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("typr/include/typr_specs_eunit.hrl").
-include_lib("typr/include/typr_specs_ct.hrl").
-include_lib("router_pb/include/registry_definitions.hrl").
-include_lib("router_grpc/include/router_grpc_service_registry.hrl").

-define(port, 8137).
-define(definition, registry_definitions).
-define(rcv_timeout, 300).

all() -> [
  {group, g_lookup_fqmn_internal},
  {group, g_register},
  {group, g_lookup_fqmn_external},
  {group, g_lookup_fqsn}
].

groups() -> [
  {g_lookup_fqmn_internal, [sequential], [
    g_lookup_fqmn_internal_registry_service
  ]},
  {g_register, [sequential], [
    g_register_stateless, g_register_stateful
  ]},
  {g_lookup_fqmn_external, [sequential], [
    g_lookup_fqmn_external_stateless, g_lookup_fqmn_external_stateful,
    g_lookup_fqmn_external_duplicate
  ]},
  {g_lookup_fqsn, [sequential], [
    g_lookup_fqsn_stateless, g_lookup_fqsn_stateful
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
  Config.

end_per_testcase(_Name, _Config) ->
  ok.

end_per_group(_Name, _Config) ->
  ok.

end_per_suite(Config) ->
  router_common_test_helper:rollback_applications_state(?config(apps_state, Config)),
  ok.



%% Group g_lookup_fqmn_internal



g_lookup_fqmn_internal_registry_service(_Config) ->
  Fqmns = [
    <<"/lg.service.router.RegistryService/RegisterVirtualService">>,
    <<"/lg.service.router.RegistryService/UnregisterVirtualService">>,
    <<"/lg.service.router.RegistryService/EnableVirtualServiceMaintenance">>,
    <<"/lg.service.router.RegistryService/DisableVirtualServiceMaintenance">>,
    <<"/lg.service.router.RegistryService/ListVirtualServices">>,
    <<"/lg.service.router.RegistryService/ControlStream">>
  ],
  [{ok, [#router_grpc_service_registry_definition_internal{}]} = router_grpc_service_registry:lookup_fqmn(Fqmn) || Fqmn <- Fqmns],
  [{ok, [#router_grpc_service_registry_definition_internal{}]} = router_grpc_service_registry:lookup_fqmn_internal(Fqmn) || Fqmn <- Fqmns],
  [{error, undefined} = router_grpc_service_registry:lookup_fqmn_external(Fqmn) || Fqmn <- Fqmns].



%% Group g_register



g_register_stateless(_Config) ->
  {ok, _} = router_grpc_service_registry:register(
    Type = stateless,
    Package = <<"lg.test">>,
    ServiceName = <<"StatelessService">>,
    _Methods = [<<"MethodOne">>, <<"MethodTwo">>],
    _Cmp = undefined,
    _Maintenance = false,
    Host = <<"test.lg">>,
    Port = 8137
  ),
  ok = router_grpc_service_registry:unregister(Type, Package, ServiceName, Host, Port).



g_register_stateful(_Config) ->
  {ok, _} = router_grpc_service_registry:register(
    Type = stateful,
    Package = <<"lg.test">>,
    ServiceName = <<"StatefulService">>,
    _Methods = [<<"MethodOne">>, <<"MethodTwo">>],
    _Cmp = 'BLOCKING',
    _Maintenance = false,
    Host = <<"test.lg">>,
    Port = 8137
  ),
  ok = router_grpc_service_registry:unregister(Type, Package, ServiceName, Host, Port).



g_lookup_fqmn_external_stateless(_Config) ->
  {ok, _} = router_grpc_service_registry:register(
    Type = stateless,
    Package = <<"lg.test">>,
    ServiceName = <<"StatelessService">>,
    _Methods = [<<"MethodOne">>, <<"MethodTwo">>],
    _Cmp = undefined,
    _Maintenance = false,
    Host = <<"test.lg">>,
    Port = 8137
  ),
  Fqmns = [
    <<"/lg.test.StatelessService/MethodOne">>,
    <<"/lg.test.StatelessService/MethodTwo">>
  ],
  [{ok, [#router_grpc_service_registry_definition_external{}]} = router_grpc_service_registry:lookup_fqmn(Fqmn) || Fqmn <- Fqmns],
  [{ok, [#router_grpc_service_registry_definition_external{}]} = router_grpc_service_registry:lookup_fqmn_external(Fqmn) || Fqmn <- Fqmns],
  [{error, undefined} = router_grpc_service_registry:lookup_fqmn_internal(Fqmn) || Fqmn <- Fqmns],
  ok = router_grpc_service_registry:unregister(Type, Package, ServiceName, Host, Port).



g_lookup_fqmn_external_stateful(_Config) ->
  {ok, _} = router_grpc_service_registry:register(
    Type = stateful,
    Package = <<"lg.test">>,
    ServiceName = <<"StatefulService">>,
    _Methods = [<<"MethodOne">>, <<"MethodTwo">>],
    _Cmp = 'BLOCKING',
    _Maintenance = false,
    Host = <<"test.lg">>,
    Port = 8137
  ),
  Fqmns = [
    <<"/lg.test.StatefulService/MethodOne">>,
    <<"/lg.test.StatefulService/MethodTwo">>
  ],
  [{ok, [#router_grpc_service_registry_definition_external{}]} = router_grpc_service_registry:lookup_fqmn(Fqmn) || Fqmn <- Fqmns],
  [{ok, [#router_grpc_service_registry_definition_external{}]} = router_grpc_service_registry:lookup_fqmn_external(Fqmn) || Fqmn <- Fqmns],
  [{error, undefined} = router_grpc_service_registry:lookup_fqmn_internal(Fqmn) || Fqmn <- Fqmns],
  ok = router_grpc_service_registry:unregister(Type, Package, ServiceName, Host, Port).



g_lookup_fqmn_external_duplicate(_Config) ->
  {ok, _} = router_grpc_service_registry:register(
    Type = stateful,
    Package = <<"lg.test">>,
    ServiceName = <<"StatefulService">>,
    Methods = [<<"MethodOne">>, <<"MethodTwo">>],
    Cmp = 'BLOCKING',
    Maintenance = false,
    Host = <<"test.lg">>,
    Port = 8137
  ),
  {ok, _} = router_grpc_service_registry:register(Type, Package, ServiceName, Methods, Cmp, Maintenance, Host, Port),
  Fqmns = [
    <<"/lg.test.StatefulService/MethodOne">>,
    <<"/lg.test.StatefulService/MethodTwo">>
  ],
  [{ok, [#router_grpc_service_registry_definition_external{}]} = router_grpc_service_registry:lookup_fqmn(Fqmn) || Fqmn <- Fqmns],
  [{ok, [#router_grpc_service_registry_definition_external{}]} = router_grpc_service_registry:lookup_fqmn_external(Fqmn) || Fqmn <- Fqmns],
  [{error, undefined} = router_grpc_service_registry:lookup_fqmn_internal(Fqmn) || Fqmn <- Fqmns],
  ok = router_grpc_service_registry:unregister(Type, Package, ServiceName, Host, Port).



%% Group g_lookup_fqsn



g_lookup_fqsn_stateless(_Config) ->
  {ok, _} = router_grpc_service_registry:register(
    Type = stateless,
    Package = <<"lg.test">>,
    ServiceName = <<"StatelessService">>,
    _Methods = [<<"MethodOne">>, <<"MethodTwo">>],
    _Cmp = undefined,
    _Maintenance = false,
    Host = <<"test.lg">>,
    Port = 8137
  ),
  FqServiceName = <<Package/binary, ".", ServiceName/binary>>,
  {ok, [#router_grpc_service_registry_definition_external{}]} = router_grpc_service_registry:lookup_fqsn(Type, FqServiceName, Host, Port),
  ok = router_grpc_service_registry:unregister(Type, Package, ServiceName, Host, Port).



g_lookup_fqsn_stateful(_Config) ->
  {ok, _} = router_grpc_service_registry:register(
    Type = stateful,
    Package = <<"lg.test">>,
    ServiceName = <<"StatefulService">>,
    _Methods = [<<"MethodOne">>, <<"MethodTwo">>],
    _Cmp = 'BLOCKING',
    _Maintenance = false,
    Host = <<"test.lg">>,
    Port = 8137
  ),
  FqServiceName = <<Package/binary, ".", ServiceName/binary>>,
  {ok, [#router_grpc_service_registry_definition_external{}]} = router_grpc_service_registry:lookup_fqsn(Type, FqServiceName, Host, Port),
  ok = router_grpc_service_registry:unregister(Type, Package, ServiceName, Host, Port).
