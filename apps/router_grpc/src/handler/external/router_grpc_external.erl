-module(router_grpc_external).


-include_lib("router_grpc/include/router_grpc.hrl").
-include_lib("router_grpc/include/router_grpc_service_registry.hrl").

-export([init/2, data/3]).

-record(router_grpc_external_state, {
  handler_pid :: pid(),
  definition :: router_grpc:definition_external(),
  agent_id :: router_grpc:agent_id() | undefined,
  agent_instance :: router_grpc:agent_instance() | undefined,
  req :: cowboy_req:req()
}).
-type state() :: #router_grpc_external_state{}.
-export_type([state/0]).


%% Interface



-spec init(
  Definitions :: [router_grpc:definition_external()],
  Req :: cowboy_req:req()
) ->
  Ret :: {HS :: state(), Definition :: router_grpc:definition_external()}.

init(Definitions, #{headers := Headers} = Req) ->
  AgentId = maps:get(?router_grpc_header_agent_id, Headers, undefined),
  AgentInstance = maps:get(?router_grpc_header_agent_instance, Headers, undefined),
  init_impl(Definitions, Req, AgentId, AgentInstance).



-spec data(
  IsFin :: boolean(),
  Data :: binary(),
  S0 :: state()
) ->
  typr:ok_return(OkRet :: state()).

data(IsFin, Data, #router_grpc_external_state{handler_pid = Pid} = S0) ->
  ok = router_grpc_external_stream_h:data(Pid, IsFin, Data),
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
  AgentId :: router_grpc:agent_id() | undefined,
  AgentInstance :: router_grpc:agent_instance() | undefined
) ->
  Ret :: {HS :: state(), Definition :: router_grpc:definition_external()}.

init_impl([#router_grpc_service_registry_definition_external{type = stateless} | _] = Definitions, Req, undefined, undefined) ->
  Definition = lists:nth(quickrand:uniform(length(Definitions)), Definitions),
  {ok, HPid} = router_grpc_external_stream_sup:start_handler(Definition, Req),
  {#router_grpc_external_state{
    handler_pid = HPid, definition = Definition, req = Req
  }, Definition};

init_impl([#router_grpc_service_registry_definition_external{type = stateful} = AnyDefinition | _] = Definitions, Req, AgentId, undefined) ->
  case router_hashring_node:lookup_agent(
    AnyDefinition#router_grpc_service_registry_definition_external.fq_service_name,
    AgentId
  ) of
    {ok, DefinitionsPL} ->
      {AgentInstance, Definition} = lists:nth(quickrand:uniform(length(DefinitionsPL)), DefinitionsPL),
      {ok, HPid} = router_grpc_external_stream_sup:start_handler(Definition, Req),
      {#router_grpc_external_state{
        handler_pid = HPid, definition = Definition, agent_id = AgentId, agent_instance = AgentInstance, req = Req
      }, Definition};
    {error, undefined} ->
      AgentInstance = router_grpc:gen_agent_instance(),
      Definition = lists:nth(quickrand:uniform(length(Definitions)), Definitions),
      {ok, HPid} = router_grpc_external_stream_sup:start_handler(Definition, Req),
      {#router_grpc_external_state{
        handler_pid = HPid, definition = Definition, agent_id = AgentId, agent_instance = AgentInstance, req = Req
      }, Definition}
  end;

init_impl([#router_grpc_service_registry_definition_external{type = stateful} = AnyDefinition | _] = Definitions, Req, AgentId, AgentInstance) ->
  case router_hashring_node:lookup_agent(
    AnyDefinition#router_grpc_service_registry_definition_external.fq_service_name,
    AgentId, AgentInstance
  ) of
    {ok, Definition} ->
      {ok, HPid} = router_grpc_external_stream_sup:start_handler(Definition, Req),
      {#router_grpc_external_state{
        handler_pid = HPid, definition = Definition, agent_id = AgentId, agent_instance = AgentInstance, req = Req
      }, Definition};
    {error, undefined} ->
      Definition = lists:nth(quickrand:uniform(length(Definitions)), Definitions),
      {ok, HPid} = router_grpc_external_stream_sup:start_handler(Definition, Req),
      {#router_grpc_external_state{
        handler_pid = HPid, definition = Definition, agent_id = AgentId, agent_instance = AgentInstance, req = Req
      }, Definition}
  end.
