-module(router_grpc_client_SUITE).
-compile([export_all, nowarn_export_all, nowarn_unused_function, nowarn_missing_spec]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("typr/include/typr_specs_eunit.hrl").
-include_lib("typr/include/typr_specs_ct.hrl").
-include_lib("router_pb/include/registry_definitions.hrl").
-include_lib("router_grpc/include/router_grpc_client.hrl").
-include_lib("router_grpc/include/router_grpc.hrl").
-include_lib("router_grpc/include/router_grpc_internal_registry.hrl").

-define(port, 8137).
-define(definition, registry_definitions).
-define(rcv_timeout, 300).

all() -> [
  {group, g_connect},
  {group, g_happy_path}
].

groups() -> [
  {g_connect, [sequential], [
    g_connect
  ]},
  {g_happy_path, [sequential], [
    g_happy_path_request, g_happy_path_multiplexed_request, g_happy_path_bistream_request
  ]}
].

init_per_suite(Config) ->
  AppsState = router_common_test_helper:init_applications_state(),
  ok = application:set_env(router_grpc, listener, [{port, ?port}], [{persistent, true}]),
  ok = application:set_env(router_grpc, client, [{pool_size, 10}], [{persistent, true}]),
  ok = application:set_env(router_grpc, session, [{inactivity_limit_ms, 15000}], [{persistent, true}]),
  ok = application:set_env(router, hashring, [{buckets_po2, 2}, {nodes_po2, 1}], [{persistent, true}]),
  {ok, _} = application:ensure_all_started(router_grpc),
  {ok, _} = application:ensure_all_started(gun),
  [{apps_state, AppsState} | Config].

init_per_group(_Name, Config) ->
  Config.

init_per_testcase(_Name, Config) ->
  erlang:process_flag(trap_exit, true),
  {ok, Client} = router_grpc_client:start_link("localhost", ?port),
  router_grpc_client:await_ready(Client, 1000),
  [{router_grpc_client, Client} | Config].

end_per_testcase(_Name, _Config) ->
  ok.

end_per_group(_Name, _Config) ->
  ok.

end_per_suite(Config) ->
  router_common_test_helper:rollback_applications_state(?config(apps_state, Config)),
  ok.



%% Group g_connect



g_connect(Config) ->
  Client = ?config(router_grpc_client, Config),
  {ok, StreamRef} = router_grpc_client:grpc_request(
    Client, self(), <<"lg.service.router.RegistryService">>, <<"RegisterVirtualService">>, #{}
  ),
  ?assert(is_reference(StreamRef)),
  router_grpc_client:grpc_terminate(Client, StreamRef).



%% Group g_happy_path



g_happy_path_request(Config) ->
  Payload = registry_definitions:encode_msg(#'lg.service.router.RegisterVirtualServiceRq'{
    virtual_service = #'lg.core.grpc.VirtualService'{
      service = {stateless, #'lg.core.grpc.VirtualService.StatelessVirtualService'{
        package = <<"foo.bar">>,
        name = <<"BazService">>,
        methods = [#'lg.core.grpc.VirtualService.Method'{name = <<"DoSomething">>}]
      }},
      endpoint = #'lg.core.network.Endpoint'{
        host = "lo",
        port = 1000
      }
    }
  }),
  Client = ?config(router_grpc_client, Config),
  {ok, StreamRef} = router_grpc_client:grpc_request(
    Client, self(), <<"lg.service.router.RegistryService">>, <<"RegisterVirtualService">>, #{}
  ),
  ok = router_grpc_client:grpc_data(Client, StreamRef, Payload),
  assert_response(StreamRef, false, 200, [?http2_header_content_type, ?grpc_header_user_agent]),
  assert_data(
    StreamRef, false, 'lg.service.router.RegisterVirtualServiceRq',
    fun(#'lg.service.router.RegisterVirtualServiceRq'{}) -> ok end
  ),
  assert_trailers(StreamRef, #{
    ?grpc_header_code => integer_to_binary(?grpc_code_ok),
    ?grpc_header_message => ?grpc_message_ok}
  ),
  assert_stream_killed(StreamRef),
  dump_msgs().



g_happy_path_multiplexed_request(Config) ->
  Payload = registry_definitions:encode_msg(#'lg.service.router.RegisterVirtualServiceRq'{
    virtual_service = #'lg.core.grpc.VirtualService'{
      service = {stateless, #'lg.core.grpc.VirtualService.StatelessVirtualService'{
        package = <<"foo.bar">>,
        name = <<"BazService">>,
        methods = [#'lg.core.grpc.VirtualService.Method'{name = <<"DoSomething">>}]
      }},
      endpoint = #'lg.core.network.Endpoint'{
        host = "lo",
        port = 1000
      }
    }
  }),
  Client = ?config(router_grpc_client, Config),
  {ok, StreamRef1} = router_grpc_client:grpc_request(
    Client, self(), <<"lg.service.router.RegistryService">>, <<"RegisterVirtualService">>, #{}
  ),
  ok = router_grpc_client:grpc_data(Client, StreamRef1, Payload),
  {ok, StreamRef2} = router_grpc_client:grpc_request(
    Client, self(), <<"lg.service.router.RegistryService">>, <<"RegisterVirtualService">>, #{}
  ),
  ok = router_grpc_client:grpc_data(Client, StreamRef2, Payload),
  assert_response(StreamRef1, false, 200, [?http2_header_content_type, ?grpc_header_user_agent]),
  assert_response(StreamRef2, false, 200, [?http2_header_content_type, ?grpc_header_user_agent]),
  assert_data(
    StreamRef1, false, 'lg.service.router.RegisterVirtualServiceRq',
    fun(#'lg.service.router.RegisterVirtualServiceRq'{}) -> ok end
  ),
  assert_data(
    StreamRef2, false, 'lg.service.router.RegisterVirtualServiceRq',
    fun(#'lg.service.router.RegisterVirtualServiceRq'{}) -> ok end
  ),
  assert_trailers(StreamRef1, #{
    ?grpc_header_code => integer_to_binary(?grpc_code_ok),
    ?grpc_header_message => ?grpc_message_ok
  }),
  assert_trailers(StreamRef2, #{
    ?grpc_header_code => integer_to_binary(?grpc_code_ok),
    ?grpc_header_message => ?grpc_message_ok
  }),
  assert_stream_killed(StreamRef1),
  assert_stream_killed(StreamRef2),
  dump_msgs().



g_happy_path_bistream_request(Config) ->
  Payload1 = registry_definitions:encode_msg(#'lg.service.router.ControlStreamEvent'{
    id = #'lg.core.trait.Id'{tag = <<"id-1">>},
    event = {init_rq, #'lg.service.router.ControlStreamEvent.InitRq'{
      virtual_service = #'lg.core.grpc.VirtualService'{
        service = {stateful, #'lg.core.grpc.VirtualService.StatefulVirtualService'{
          package = <<"foo.bar">>,
          name = <<"BazService">>,
          methods = [#'lg.core.grpc.VirtualService.Method'{name = <<"DoSomething">>}],
          cmp = 'BLOCKING'
        }},
        endpoint = #'lg.core.network.Endpoint'{
          host = "lo",
          port = 1000
        }
      }
    }
  }}),
  Client = ?config(router_grpc_client, Config),
  {ok, StreamRef} = router_grpc_client:grpc_request(
    Client, self(), <<"lg.service.router.RegistryService">>, <<"ControlStream">>, #{}
  ),
  ok = router_grpc_client:grpc_data(Client, StreamRef, Payload1),
  assert_response(StreamRef, false, 200, [?http2_header_content_type, ?grpc_header_user_agent]),
  assert_data(
    StreamRef, false, 'lg.service.router.ControlStreamEvent',
    fun(#'lg.service.router.ControlStreamEvent'{
      id = #'lg.core.trait.Id'{tag = <<"id-1">>},
      event = {init_rs, #'lg.service.router.ControlStreamEvent.InitRs'{
        session_id = SessionId,
        result = #'lg.core.trait.Result'{status = 'SUCCESS'}
      }}
    }) ->
      ?assertNotEqual(<<>>, SessionId)
    end
  ),
  router_grpc_client:grpc_terminate(Client, StreamRef),
  dump_msgs().



%% Helpers



assert_response(StreamRef, IsFin, Status, Headers) ->
  receive
    ?grpc_event_response(StreamRef, IsFin_, Status_, Headers_) ->
      ?assertEqual(IsFin, IsFin_),
      ?assertEqual(Status, Status_),
      [?assert(maps:is_key(Header, Headers_)) || Header <- Headers]
  after ?rcv_timeout ->
    dump_msgs(),
    error(didnt_get_grpc_response)
  end.



assert_data(StreamRef, IsFin, Type, DataFn) ->
  receive
    ?grpc_event_data(StreamRef, IsFin_, Data) ->
      ?assertEqual(IsFin, IsFin_),
      DataFn(?definition:decode_msg(Data, Type))
  after ?rcv_timeout ->
    dump_msgs(),
    error(didnt_get_grpc_data)
  end.



assert_trailers(StreamRef, Trailers) ->
  receive
    ?grpc_event_trailers(StreamRef, Trailers_) ->
      maps:foreach(fun(TK, TV) ->
        ?assertEqual(TV, maps:get(TK, Trailers_, undefined))
      end, Trailers)
  after ?rcv_timeout ->
    dump_msgs(),
    error(didnt_get_grpc_trailers)
  end.



assert_stream_killed(StreamRef) ->
  receive
    ?grpc_event_stream_killed(StreamRef) -> ok
  after ?rcv_timeout ->
    dump_msgs(),
    error(didnt_get_stream_kill)
  end.



dump_msgs() ->
  receive
    Msg -> error({got_extra_message, Msg})
  after ?rcv_timeout * 3 -> ok
  end.
