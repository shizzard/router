-module(router_grpc_external).


-include_lib("router_log/include/router_log.hrl").
-include_lib("router_grpc/include/router_grpc.hrl").
-include_lib("router_grpc/include/router_grpc_service_registry.hrl").
-include_lib("router_grpc/include/router_grpc_external_context.hrl").

-export([init/2, data/3]).

-record(router_grpc_external_state, {
  handler_pid :: pid(),
  definition :: router_grpc:definition_external(),
  ctx :: router_grpc_external_context:t(),
  req :: cowboy_req:req()
}).
-type state() :: #router_grpc_external_state{}.
-export_type([state/0]).


%% Interface



-spec init(
  Definitions :: [router_grpc:definition_external()],
  Req :: cowboy_req:req()
) ->
  typr:generic_return(
    OkRet :: {HS :: state(), Definition :: router_grpc:definition_external()},
    ErrorRet :: agent_spec_missing
  ).

init(Definitions, #{headers := Headers} = Req) ->
  AgentId = maps:get(?router_grpc_header_agent_id, Headers, undefined),
  AgentInstance = maps:get(?router_grpc_header_agent_instance, Headers, undefined),
  RequestId = maps:get(?router_grpc_header_agent_instance, Headers,
    uuid:uuid_to_string(uuid:get_v4_urandom(), binary_standard)),
  Ctx = #router_grpc_external_context{
    agent_id = AgentId, agent_instance = AgentInstance, request_id = RequestId
  },
  init_impl(Definitions, Req, Ctx).



-spec data(
  IsFin :: boolean(),
  Data :: binary(),
  S0 :: state()
) ->
  typr:ok_return(OkRet :: state()).

data(IsFin, Data, #router_grpc_external_state{definition = Definition, handler_pid = HPid} = S0) ->
  ?l_debug(#{text => "External virtual service call data", what => init, details => #{
    service => Definition#router_grpc_service_registry_definition_external.fq_service_name,
    host => Definition#router_grpc_service_registry_definition_external.host,
    port => Definition#router_grpc_service_registry_definition_external.port,
    handler_pid => HPid
  }}),
  ok = router_grpc_external_stream_h:data(HPid, IsFin, Data),
  {ok, S0}.



%% Internals



%% Core idea behind this code is the following:
%% - for stateless services client can route a request towards any suitable virtual service;
%% - for stateful services client can route a request towards some agent only
%%   (e.g. headers indicating agent id and agent instance are obligatory);
%% - target agent might have a specified instance (full id) or not (bare id);
%%   - for full id we need to lookup for exactly one agent (agent_id@fqsn/agent_instance);
%%   - for bare id we need to lookup for any agent (agent_id@fqsn/<any_instance>);
%% - if required agent was found, route request towards virtual service specified by definition;
%% - if no agent was found, route request towards random virtual service that match the requested service.
%% All data passing back and forth is directed via `router_grpc_external_stream_h` instance.
-spec init_impl(
  Definitions :: [router_grpc:definition_external()],
  Req :: cowboy_req:req(),
  Ctx :: router_grpc_external_context:t()
) ->
  typr:generic_return(
    OkRet :: {HS :: state(), Definition :: router_grpc:definition_external()},
    ErrorRet :: agent_spec_missing | term()
  ).

init_impl(
  [#router_grpc_service_registry_definition_external{type = stateless} | _] = Definitions, Req,
  #router_grpc_external_context{agent_id = _, agent_instance = _} = Ctx0
) ->
  %% Stateless service call
  Definition = lists:nth(quickrand:uniform(length(Definitions)), Definitions),
  {ok, HPid} = router_grpc_external_stream_sup:start_handler(Definition, Req, Ctx0),
  {ok, {#router_grpc_external_state{
    handler_pid = HPid, definition = Definition, req = Req, ctx = Ctx0
  }, Definition}};

init_impl(
  [#router_grpc_service_registry_definition_external{type = stateful} | _] = _Definitions, _Req,
  #router_grpc_external_context{agent_id = undefined, agent_instance = undefined} = _Ctx0
) ->
  %% Stateful service call with no agent info specified
  {error, agent_spec_missing};

init_impl(
  [#router_grpc_service_registry_definition_external{type = stateful} = AnyDefinition | _] = Definitions, Req,
  #router_grpc_external_context{agent_id = AgentId, agent_instance = undefined} = Ctx0
) ->
  %% Bare agent call, as agent instance is not set
  case router_hashring_node:lookup_agent(
    AnyDefinition#router_grpc_service_registry_definition_external.fq_service_name,
    AgentId
  ) of
    {ok, DefinitionsPL} ->
      %% Found a list of corresponding agents (e.g. matching agent id with different agent instances)
      %% Choose a random one and proceed
      {AgentInstance, Definition} = lists:nth(quickrand:uniform(length(DefinitionsPL)), DefinitionsPL),
      Ctx1 = Ctx0#router_grpc_external_context{agent_instance = AgentInstance},
      {ok, HPid} = router_grpc_external_stream_sup:start_handler(Definition, Req, Ctx1),
      {ok, {#router_grpc_external_state{
        handler_pid = HPid, definition = Definition, ctx = Ctx1, req = Req
      }, Definition}};
    {error, undefined} ->
      %% No matching agent found
      %% Choose a random stateful virtual service instance and proceed with generated agent instance
      Definition = lists:nth(quickrand:uniform(length(Definitions)), Definitions),
      AgentInstance = router_grpc:gen_agent_instance(),
      Ctx1 = Ctx0#router_grpc_external_context{agent_instance = AgentInstance},
      {ok, HPid} = router_grpc_external_stream_sup:start_handler(Definition, Req, Ctx1),
      {ok, {#router_grpc_external_state{
        handler_pid = HPid, definition = Definition, ctx = Ctx1, req = Req
      }, Definition}}
  end;

init_impl(
  [#router_grpc_service_registry_definition_external{type = stateful} = AnyDefinition | _] = Definitions, Req,
  #router_grpc_external_context{agent_id = AgentId, agent_instance = AgentInstance} = Ctx0
) ->
  %% Full agent call
  case router_hashring_node:lookup_agent(
    AnyDefinition#router_grpc_service_registry_definition_external.fq_service_name,
    AgentId, AgentInstance
  ) of
    {ok, Definition} ->
      %% Agent found (e.g. both agent id and agent instance matched)
      %% Proceed with the chosen agent
      {ok, HPid} = router_grpc_external_stream_sup:start_handler(Definition, Req, Ctx0),
      {ok, {#router_grpc_external_state{
        handler_pid = HPid, definition = Definition, ctx = Ctx0, req = Req
      }, Definition}};
    {error, undefined} ->
      %% No matching agent found
      %% Choose a random stateful virtual service and proceed with the specified agent id and instance
      Definition = lists:nth(quickrand:uniform(length(Definitions)), Definitions),
      {ok, HPid} = router_grpc_external_stream_sup:start_handler(Definition, Req, Ctx0),
      {ok, {#router_grpc_external_state{
        handler_pid = HPid, definition = Definition, ctx = Ctx0, req = Req
      }, Definition}}
  end.
