-module(router_grpc_stream_h).
-behaviour(gen_server).

-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").
-include_lib("router_pb/include/registry_definitions.hrl").
-include("router_grpc_h_registry.hrl").
-include("router_grpc_service_registry.hrl").

-export([lookup/1, recover/3, register_agent/4, unregister_agent/4, conflict/4]).
-export([
  start_link/5, init/1,
  handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3
]).

-record(state, {
  session_id :: session_id(),
  definition_internal :: router_grpc:definition_internal(),
  definition_external :: router_grpc:definition_external(),
  conflict_fun = fun conflict/4 :: conflict_fun(),
  conn_pid :: pid() | undefined,
  conn_req :: cowboy_req:req(),
  conn_monitor_ref :: reference() | undefined,
  session_inactivity_limit_ms :: pos_integer(),
  session_ref :: reference() | undefined,
  session_timer_ref :: reference() | undefined
}).
-type state() :: #state{}.

-type session_id() :: binary().
-type conflict_fun() :: fun((
    StreamPid :: pid(),
    Fqsn :: router_grpc:fq_service_name(),
    AgentId :: router_grpc:agent_id(),
    AgentInstance :: router_grpc:agent_instance()
  ) -> ok).
-export_type([session_id/0, conflict_fun/0]).

-define(gproc_key(Id), {?MODULE, Id}).
-define(agent_key(Fqsn, AgentId, AgentInstance),
  {agent_key, Fqsn, AgentId, AgentInstance}).



%% Messages



-define(msg_session_inactivity_trigger(Ref), {msg_session_inactivity_trigger, Ref}).
-define(msg_recover(SessionId, ConnPid), {msg_recover, SessionId, ConnPid}).
-define(msg_register_agent(Fqsn, AgentId, AgentInstance), {msg_register_agent, Fqsn, AgentId, AgentInstance}).
-define(msg_unregister_agent(Fqsn, AgentId, AgentInstance), {msg_unregister_agent, Fqsn, AgentId, AgentInstance}).
-define(msg_conflict(Fqsn, AgentId, AgentInstance), {msg_conflict, Fqsn, AgentId, AgentInstance}).



%% Metrics



%% Interface



-spec lookup(SessionId :: session_id()) ->
  Ret :: pid() | undefined.

lookup(SessionId) -> gproc:where({n, l, ?gproc_key(SessionId)}).



-spec recover(
  Pid :: pid(),
  SessionId :: router_grpc_stream_h:session_id(),
  ConnPid :: pid()
) ->
  typr:generic_return(
    ErrorRet :: conn_alive
  ).

recover(Pid, SessionId, ConnPid) ->
  gen_server:call(Pid, ?msg_recover(SessionId, ConnPid)).



-spec register_agent(
  Pid :: pid(),
  Fqsn :: router_grpc:fq_service_name(),
  AgentId :: router_grpc:agent_id(),
  AgentInstance :: router_grpc:agent_instance()
) ->
  typr:generic_return(
    OkRet :: {
      AgentId :: router_grpc:agent_id(),
      AgentInstance :: router_grpc:agent_instance()
    },
    ErrorRet :: conflict | internal_error
  ).

register_agent(Pid, Fqsn, AgentId, AgentInstance) ->
  gen_server:call(Pid, ?msg_register_agent(Fqsn, AgentId, AgentInstance)).



-spec unregister_agent(
  Pid :: pid(),
  Fqsn :: router_grpc:fq_service_name(),
  AgentId :: router_grpc:agent_id(),
  AgentInstance :: router_grpc:agent_instance()
) ->
  typr:generic_return(
    OkRet :: {
      AgentId :: router_grpc:agent_id(),
      AgentInstance :: router_grpc:agent_instance()
    },
    ErrorRet :: internal_error
  ).

unregister_agent(Pid, Fqsn, AgentId, AgentInstance) ->
  gen_server:call(Pid, ?msg_unregister_agent(Fqsn, AgentId, AgentInstance)).



-spec conflict(
  StreamPid :: pid(),
  Fqsn :: router_grpc:fq_service_name(),
  AgentId :: router_grpc:agent_id(),
  AgentInstance :: router_grpc:agent_instance()
) ->
  typr:ok_return().

conflict(StreamPid, Fqsn, AgentId, AgentInstance) ->
  gen_server:cast(StreamPid, ?msg_conflict(Fqsn, AgentId, AgentInstance)).



-spec start_link(
  SessionId :: session_id(),
  DefinitionInternal :: router_grpc:definition_internal(),
  DefinitionExternal :: router_grpc:definition_external(),
  ConnReq :: cowboy_req:req(),
  ConnPid :: pid()
) ->
  typr:ok_return(OkRet :: pid()).

start_link(SessionId, DefinitionInternal, DefinitionExternal, ConnReq, ConnPid) ->
  gen_server:start_link(?MODULE, {SessionId, DefinitionInternal, DefinitionExternal, ConnReq, ConnPid}, []).



init({SessionId, DefinitionInternal, DefinitionExternal, ConnReq, ConnPid}) ->
  router_log:component(router_grpc),
  ok = quickrand:seed(),
  ok = init_prometheus_metrics(),
  {ok, Limit} = router_config:get(router_grpc, [session, inactivity_limit_ms]),
  S0 = #state{
    session_id = SessionId,
    definition_internal = DefinitionInternal, definition_external = DefinitionExternal,
    conn_pid = ConnPid, conn_req = ConnReq,
    session_inactivity_limit_ms = Limit
  },
  case init_register(S0) of
    {ok, S1} ->
      ?l_debug(#{
        text => "gRPC stream handler registered", what => init,
        result => ok, details => #{stream_id => SessionId, conn_pid => ConnPid}
      }),
      {ok, S1};
    {error, Reason} ->
      ?l_warning(#{
        text => "Failed to register gRPC stream handler", what => init,
        result => error, details => #{reason => Reason}
      }),
      ignore
  end.



init_register(S0) ->
  case lookup(S0#state.session_id) of
    undefined ->
      true = gproc:reg({n, l, ?gproc_key(S0#state.session_id)}),
      {ok, init_conn_monitor(S0)};
    Pid ->
      {error, {already_started, S0#state.session_id, Pid}}
  end.



%% Handlers



%% ConnPid dead, session id and endpoint params are correct: successful recover
handle_call(?msg_recover(SessionId, ConnPid), _GenReplyTo, #state{
  session_id = SessionId, conn_pid = undefined, conn_monitor_ref = undefined
} = S0) ->
  {reply, ok, init_conn_monitor(S0#state{conn_pid = ConnPid})};

%% ConnPid alive, refuse the recovery
handle_call(?msg_recover(SessionId, _ConnPid), _GenReplyTo, #state{session_id = SessionId} = S0) ->
  {reply, {error, conn_alive}, S0};

handle_call(?msg_register_agent(Fqsn, AgentId, undefined), _GenReplyTo, #state{
  definition_external = Definition
} = S0) ->
  AgentInstance = list_to_binary(uuid:uuid_to_string(uuid:get_v4_urandom())),
  handle_call_register_agent(Fqsn, AgentId, AgentInstance, Definition, S0);

handle_call(?msg_register_agent(Fqsn, AgentId, AgentInstance), _GenReplyTo, #state{
  definition_external = Definition
} = S0) ->
  handle_call_register_agent(Fqsn, AgentId, AgentInstance, Definition, S0);

handle_call(?msg_unregister_agent(Fqsn, AgentId, AgentInstance), _GenReplyTo, S0) ->
  handle_call_unregister_agent(Fqsn, AgentId, AgentInstance, S0);

handle_call(Unexpected, _GenReplyTo, S0) ->
  ?l_error(#{text => "Unexpected call", what => handle_call, details => Unexpected}),
  {reply, badarg, S0}.



handle_cast(?msg_conflict(_Fqsn, AgentId, AgentInstance), S0) ->
  router_grpc_h:push_data(#'lg.service.router.ControlStreamEvent'{
    id = #'lg.core.trait.Id'{tag = list_to_binary(uuid:uuid_to_string(uuid:get_v4_urandom()))},
    event = {conflict_event, #'lg.service.router.ControlStreamEvent.ConflictEvent'{
      agent_id = AgentId, agent_instance = AgentInstance,
      reason = ?control_stream_conflict_event_reason_preemptive
    }}
  }, S0#state.conn_req),
  {noreply, S0};

handle_cast(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected cast", what => handle_cast, details => Unexpected}),
  {noreply, S0}.



handle_info(?msg_session_inactivity_trigger(Ref), #state{
  session_inactivity_limit_ms = Limit, session_ref = Ref
} = S0) ->
  ?l_debug(#{
    text => "Stream session expired", what => handle_info,
    details => #{stream_id => S0#state.session_id, inactivity_limit_ms => Limit}
  }),
  {stop, shutdown, S0};

handle_info({'DOWN', Ref, process, Pid, Reason}, #state{conn_monitor_ref = Ref} = S0) ->
  ?l_debug(#{
    text => "Connection process terminated", what => handle_info,
    details => #{conn_pid => Pid, reason => Reason}
  }),
  {ok, S1} = init_session_timer(S0),
  {noreply, S1#state{conn_pid = undefined, conn_monitor_ref = undefined}};

handle_info(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected info", what => handle_info, details => Unexpected}),
  {noreply, S0}.



terminate(_Reason, _S0) ->
  ok.



code_change(_OldVsn, S0, _Extra) ->
  {ok, S0}.



%% Internals



init_session_timer(#state{
  session_inactivity_limit_ms = Limit,
  session_ref = undefined,
  session_timer_ref = undefined
} = S0) ->
  Ref = erlang:make_ref(),
  TRef = erlang:send_after(Limit, self(), ?msg_session_inactivity_trigger(Ref)),
  {ok, S0#state{session_ref = Ref, session_timer_ref = TRef}};

init_session_timer(#state{
  session_timer_ref = OldTref
} = S0) ->
  _ = erlang:cancel_timer(OldTref),
  init_session_timer(S0#state{session_ref = undefined, session_timer_ref = undefined}).



init_conn_monitor(S0) ->
  S0#state{conn_monitor_ref = erlang:monitor(process, S0#state.conn_pid)}.



init_prometheus_metrics() ->
  ok.



handle_call_register_agent(Fqsn, AgentId, AgentInstance, Definition, S0) ->
  AgentKey = ?agent_key(Fqsn, AgentId, AgentInstance),
  {ok, HR} = router_hashring:get(),
  {Node, Bucket} = router_hashring_po2:map(HR, AgentKey),
  case router_hashring_node:register_agent(Node, Bucket, Definition, AgentId, AgentInstance, S0#state.conflict_fun) of
    ok ->
      ?l_debug(#{
        text => "Agent registered", what => handle_call,
        details => #{fq_service_name => Fqsn, agent_id => AgentId, agent_instance => AgentInstance}
      }),
      {reply, {ok, {AgentId, AgentInstance}}, S0};
    {error, conflict} ->
      ?l_debug(#{
        text => "Failed to register agent: conflict", what => handle_call,
        details => #{fq_service_name => Fqsn, agent_id => AgentId, agent_instance => AgentInstance}
      }),
      {reply, {error, conflict}, S0};
    {error, invalid_node} ->
      ?l_error(#{
        text => "Failed to register agent: invalid node", what => handle_call,
        details => #{
          fq_service_name => Fqsn, agent_id => AgentId, agent_instance => AgentInstance,
          hashring => #{node => Node, bucket => Bucket}
        }
      }),
      {reply, {error, internal_error}, S0};
    {error, invalid_bucket} ->
      ?l_error(#{
        text => "Failed to register agent: invalid bucket", what => handle_call,
        details => #{
          fq_service_name => Fqsn, agent_id => AgentId, agent_instance => AgentInstance,
          hashring => #{node => Node, bucket => Bucket}
        }
      }),
      {reply, {error, internal_error}, S0}
  end.



handle_call_unregister_agent(Fqsn, AgentId, AgentInstance, S0) ->
  AgentKey = ?agent_key(Fqsn, AgentId, AgentInstance),
  {ok, HR} = router_hashring:get(),
  {Node, Bucket} = router_hashring_po2:map(HR, AgentKey),
  case router_hashring_node:unregister_agent(Node, Bucket, Fqsn, AgentId, AgentInstance) of
    ok -> {reply, {ok, {AgentId, AgentInstance}}, S0};
    {error, invalid_node} ->
      ?l_error(#{
        text => "Failed to unregister agent: invalid node", what => handle_call,
        details => #{
          fq_service_name => Fqsn, agent_id => AgentId, agent_instance => AgentInstance,
          hashring => #{node => Node, bucket => Bucket}
        }
      }),
      {reply, {error, internal_error}, S0};
    {error, invalid_bucket} ->
      ?l_error(#{
        text => "Failed to unregister agent: invalid bucket", what => handle_call,
        details => #{
          fq_service_name => Fqsn, agent_id => AgentId, agent_instance => AgentInstance,
          hashring => #{node => Node, bucket => Bucket}
        }
      }),
      {reply, {error, internal_error}, S0}
  end.
