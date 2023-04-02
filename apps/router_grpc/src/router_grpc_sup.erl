-module('router_grpc_sup').
-behaviour(supervisor).

-include_lib("router_log/include/router_log.hrl").
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
  router_log:component(router_grpc),

  ok = init_prometheus_metrics(),
  {ok, Port} = router_config:get(router_grpc, [listener, port]),
  ok = start_cowboy(Port),
  ?l_info(#{text => "gRPC listener started", what => init, result => ok, details => #{port => Port}}),

  SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
  Children = [
    #{
      id => router_grpc_service_registry,
      start => {router_grpc_service_registry, start_link, [
        [registry_definitions],
        #{'lg.service.router.RegistryService' => router_grpc_h_registry}
      ]},
      restart => permanent,
      shutdown => 5000,
      type => worker
    }
    % ranch_server_child_spec()
  ],
  {ok, {SupFlags, Children}}.



%% Internals



start_cowboy(Port) ->
  {ok, _} = cowboy:start_clear(router_grpc_listener,
    [{port, Port}],
    #{
      env => #{dispatch => cowboy_router:compile([])},
      stream_handlers => [router_grpc_h]
    }
  ),
  ok.



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
