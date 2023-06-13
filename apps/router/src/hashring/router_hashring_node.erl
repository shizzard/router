-module(router_hashring_node).
-behaviour(gen_server).

-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").
-include_lib("router_grpc/include/router_grpc_service_registry.hrl").

-export([register_agent/4, unregister_agent/3, lookup_agent/3, lookup_agent/2]).
-export([
  start_link/2, init/1,
  handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3
]).

-record(state, {
  id :: atom(),
  node :: router_hashring_po2:hr_node(),
  buckets :: [router_hashring_po2:hr_bucket(), ...],
  bucket_ets :: #{router_hashring_po2:hr_bucket() => ets:tid()} | undefined
}).
-type state() :: #state{}.


-export_type([]).

-define(agent_record_id(Fqsn, AgentId, AgentInstance), {Fqsn, AgentId, AgentInstance}).
-record(agent_record, {
  id :: ?agent_record_id(
    Fqsn :: router_grpc:fq_service_name(),
    AgentId :: router_grpc:agent_id(),
    AgentInstance :: router_grpc:agent_instance()
  ),
  stream_h_pid :: pid(),
  conflict_fun :: router_grpc_internal_stream_h:conflict_fun(),
  monitor_ref :: reference(),
  service_definition :: router_grpc:definition_external(),
  agent_id :: router_grpc:agent_id(),
  agent_instance :: router_grpc:agent_instance()
}).

-define(agent_hashring_key(Fqsn, AgentId), {agent_hashring_key, Fqsn, AgentId}).
-define(gproc_key(Node), {?MODULE, Node}).
-define(stream_down_monitor_tag(Bucket, AgentRecordId), {stream_down_monitor_tag, Bucket, AgentRecordId}).



%% Messages



-define(msg_register_agent(StreamPid, Bucket, Definition, AgentId, AgentInstance, ConflictFun),
  {msg_register_agent, StreamPid, Bucket, Definition, AgentId, AgentInstance, ConflictFun}).
-define(msg_unregister_agent(Bucket, Fqsn, AgentId, AgentInstance),
  {msg_unregister_agent, Bucket, Fqsn, AgentId, AgentInstance}).
-define(msg_lookup_agent(Bucket, Fqsn, AgentId, AgentInstance),
  {msg_lookup_agent, Bucket, Fqsn, AgentId, AgentInstance}).
-define(msg_lookup_agent(Bucket, Fqsn, AgentId),
  {msg_lookup_agent, Bucket, Fqsn, AgentId}).



%% Metrics



%% Interface



-spec register_agent(
  Definition :: router_grpc:definition_external(),
  AgentId :: router_grpc:agent_id(),
  AgentInstance :: router_grpc:agent_instance(),
  ConflictFun :: router_grpc_internal_stream_h:conflict_fun()
) ->
  typr:generic_return(
    ErrorRet :: invalid_node | invalid_bucket | conflict
  ).

register_agent(Definition, AgentId, AgentInstance, ConflictFun) ->
  {Node, Bucket} = map(Definition#router_grpc_service_registry_definition_external.fq_service_name, AgentId),
  maybe_call_node(Node, ?msg_register_agent(self(), Bucket, Definition, AgentId, AgentInstance, ConflictFun)).



-spec unregister_agent(
  Fqsn :: router_grpc:fq_service_name(),
  AgentId :: router_grpc:agent_id(),
  AgentInstance :: router_grpc:agent_instance()
) ->
  typr:generic_return(
    ErrorRet :: invalid_node | invalid_bucket
  ).

unregister_agent(Fqsn, AgentId, AgentInstance) ->
  {Node, Bucket} = map(Fqsn, AgentId),
  maybe_call_node(Node, ?msg_unregister_agent(Bucket, Fqsn, AgentId, AgentInstance)).



-spec lookup_agent(
  Fqsn :: router_grpc:fq_service_name(),
  AgentId :: router_grpc:agent_id(),
  AgentInstance :: router_grpc:agent_instance()
) ->
  typr:generic_return(
    OkRet :: router_grpc:definition_external(),
    ErrorRet :: invalid_node | invalid_bucket | undefined
  ).

lookup_agent(Fqsn, AgentId, AgentInstance) ->
  {Node, Bucket} = map(Fqsn, AgentId),
  maybe_call_node(Node, ?msg_lookup_agent(Bucket, Fqsn, AgentId, AgentInstance)).



-spec lookup_agent(
  Fqsn :: router_grpc:fq_service_name(),
  AgentId :: router_grpc:agent_id()
) ->
  typr:generic_return(
    OkRet :: [{router_grpc:agent_instance(), router_grpc:definition_external()}],
    ErrorRet :: invalid_node | invalid_bucket | undefined
  ).

lookup_agent(Fqsn, AgentId) ->
  {Node, Bucket} = map(Fqsn, AgentId),
  maybe_call_node(Node, ?msg_lookup_agent(Bucket, Fqsn, AgentId)).



-spec start_link(
  HRSpec :: router_hashring_po2:hr_node_buckets_spec(),
  Id :: atom()
) ->
  typr:ok_return(OkRet :: pid()).

start_link(HRSpec, Id) ->
  gen_server:start_link({local, Id}, ?MODULE, {HRSpec, Id}, []).



init({#{buckets := Buckets, node := Node}, Id}) ->
  router_log:component(router_hashring),
  ok = quickrand:seed(),
  ok = init_prometheus_metrics(),
  S0 = #state{id = Id, node = Node, buckets = Buckets},
  S1 = init_bucket_ets(S0),
  case init_register(Node, S1) of
    {ok, S2} ->
      ?l_debug(#{text => "Node started", what => handle_call, details => #{node => Node}}),
      {ok, S2};
    {error, Reason} ->
      ?l_error(#{text => "Node already started", what => handle_call, details => #{reason => Reason, node => Node}}),
      ignore
  end.



%% Handlers



handle_call(?msg_register_agent(StreamPid, Bucket, Definition, AgentId, AgentInstance, ConflictFun), _GenReplyTo, #state{
  bucket_ets = BucketEts
} = S0) ->
  case BucketEts of
    #{Bucket := Ets} ->
      handle_call_register_agent(Ets, StreamPid, Bucket, Definition, AgentId, AgentInstance, ConflictFun, S0);
    _ ->
      ?l_error(#{
        text => "Failed to register agent: invalid bucket", what => handle_call, details => #{
          bucket => Bucket, node => S0#state.id, actual_buckets => S0#state.buckets
        }
      }),
      {reply, {error, invalid_bucket}, S0}
  end;

handle_call(?msg_unregister_agent(Bucket, Fqsn, AgentId, AgentInstance), _GenReplyTo, #state{
  bucket_ets = BucketEts
} = S0) ->
  case BucketEts of
    #{Bucket := Ets} ->
      handle_call_unregister_agent(Ets, Fqsn, AgentId, AgentInstance, S0);
    _ ->
      {reply, {error, invalid_bucket}, S0}
  end;

handle_call(?msg_lookup_agent(Bucket, Fqsn, AgentId, AgentInstance), _GenReplyTo, #state{
  bucket_ets = BucketEts
} = S0) ->
  case BucketEts of
    #{Bucket := Ets} ->
      handle_call_lookup_agent(Ets, Fqsn, AgentId, AgentInstance, S0);
    _ ->
      {reply, {error, invalid_bucket}, S0}
  end;

handle_call(?msg_lookup_agent(Bucket, Fqsn, AgentId), _GenReplyTo, #state{
  bucket_ets = BucketEts
} = S0) ->
  case BucketEts of
    #{Bucket := Ets} ->
      handle_call_lookup_agent(Ets, Fqsn, AgentId, S0);
    _ ->
      {reply, {error, invalid_bucket}, S0}
  end;

handle_call(Unexpected, _GenReplyTo, S0) ->
  ?l_error(#{text => "Unexpected call", what => handle_call, details => Unexpected}),
  {reply, badarg, S0}.



handle_cast(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected cast", what => handle_cast, details => Unexpected}),
  {noreply, S0}.



handle_info({?stream_down_monitor_tag(Bucket, AgentRecordId), _MonRef, process, StreamPid, Reason}, #state{
  bucket_ets = BucketEts
} = S0) ->
  ?l_warning(#{text => "Stream down, performing cleanup", what => handle_info, details => #{
    bucket => Bucket, stream_pid => StreamPid, reason => Reason
  }}),
  case BucketEts of
    #{Bucket := Ets} ->
      true = ets:delete(Ets, AgentRecordId);
    _ -> ok
  end,
  {noreply, S0};

handle_info(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected info", what => handle_info, details => Unexpected}),
  {noreply, S0}.



terminate(_Reason, _S0) ->
  ok.



code_change(_OldVsn, S0, _Extra) ->
  {ok, S0}.



%% Internals



init_prometheus_metrics() ->
  ok.



init_bucket_ets(#state{buckets = Buckets} = S0) ->
  S0#state{
    bucket_ets = maps:from_list([
      {Bucket, ets:new(router_hashring_node_bucket,
        [ordered_set, protected, {read_concurrency, true},
        {keypos, #agent_record.id}]
      )}
    || Bucket <- Buckets])
  }.



init_register(Node, S0) ->
  case lookup(Node) of
    undefined ->
      true = gproc:reg({n, l, ?gproc_key(Node)}),
      {ok, S0};
    Pid ->
      {error, {already_started, Pid}}
  end.



lookup(Node) ->
  gproc:where({n, l, ?gproc_key(Node)}).



maybe_call_node(Node, Message) ->
  case lookup(Node) of
    undefined -> {error, invalid_node};
    Pid -> gen_server:call(Pid, Message)
  end.



handle_call_register_agent(Ets, StreamPid, Bucket, #router_grpc_service_registry_definition_external{
  fq_service_name = Fqsn, cmp = 'BLOCKING'
} = Definition, AgentId, AgentInstance, ConflictFun, S0) ->
  AgentRecordId = ?agent_record_id(Fqsn, AgentId, AgentInstance),
  MonRef = erlang:monitor(process, StreamPid, [{tag, ?stream_down_monitor_tag(Bucket, AgentRecordId)}]),
  case ets:insert_new(Ets, #agent_record{
    id = AgentRecordId, stream_h_pid = StreamPid, conflict_fun = ConflictFun, monitor_ref = MonRef,
    service_definition = Definition, agent_id = AgentId, agent_instance = AgentInstance
  }) of
    true ->
      {reply, ok, S0};
    false ->
      true = erlang:demonitor(MonRef, [flush]),
      {reply, {error, conflict}, S0}
  end;

handle_call_register_agent(Ets, StreamPid, Bucket, #router_grpc_service_registry_definition_external{
  fq_service_name = Fqsn, cmp = 'PREEMPTIVE'
} = Definition, AgentId, AgentInstance, ConflictFun, S0) ->
  AgentRecordId = ?agent_record_id(Fqsn, AgentId, AgentInstance),
  MonRef = erlang:monitor(process, StreamPid, [{tag, ?stream_down_monitor_tag(Bucket, AgentRecordId)}]),
  AgentRecord = #agent_record{
    id = AgentRecordId, stream_h_pid = StreamPid, conflict_fun = ConflictFun, monitor_ref = MonRef,
    service_definition = Definition, agent_id = AgentId, agent_instance = AgentInstance
  },
  case ets:lookup(Ets, AgentRecordId) of
    [] ->
      true = ets:insert_new(Ets, AgentRecord),
      {reply, ok, S0};
    [#agent_record{
      stream_h_pid = StreamPid_, conflict_fun = ConflictFun_, monitor_ref = MonRef_,
      agent_id = AgentId_, agent_instance = AgentInstance_
    }] ->
      ok = ConflictFun_(StreamPid_, Fqsn, AgentId_, AgentInstance_),
      true = erlang:demonitor(MonRef_, [flush]),
      true = ets:insert(Ets, AgentRecord),
      {reply, ok, S0}
  end.



handle_call_unregister_agent(Ets, Fqsn, AgentId, AgentInstance, S0) ->
  AgentRecordId = ?agent_record_id(Fqsn, AgentId, AgentInstance),
  true = ets:delete(Ets, AgentRecordId),
  {reply, ok, S0}.



handle_call_lookup_agent(Ets, Fqsn, AgentId, AgentInstance, S0) ->
  AgentRecordId = ?agent_record_id(Fqsn, AgentId, AgentInstance),
  case ets:lookup(Ets, AgentRecordId) of
    [] -> {reply, {error, undefined}, S0};
    [#agent_record{service_definition = Definition}] ->
      {reply, {ok, Definition}, S0}
  end.



handle_call_lookup_agent(Ets, Fqsn, AgentId, S0) ->
  case ets:select(Ets, lookup_agent_match_spec(Fqsn, AgentId)) of
    [] ->
      {reply, {error, undefined}, S0};
    List ->
      {reply, {ok, [
        {AgentInstance, Definition}
        || #agent_record{agent_instance = AgentInstance, service_definition = Definition} <- List
      ]}, S0}
  end.



map(Fqsn, AgentId) ->
  AgentKey = ?agent_hashring_key(Fqsn, AgentId),
  {ok, HR} = router_hashring:get(),
  router_hashring_po2:map(HR, AgentKey).



%% This function causes dialyzer error regarding record construction:
%% > Record construction
%% > #agent_record{... :: '_'}
%% > violates the declared type of ...
-dialyzer({nowarn_function, [lookup_agent_match_spec/2]}).

% ets:fun2ms(
%   fun(#agent_record{id = ?agent_record_id(Fqsn_, AgentId_, '_'), _ = '_'} = Obj)
%   when Fqsn == Fqsn_, AgentId == AgentId_ ->
%     Obj
%   end
% )
lookup_agent_match_spec(Fqsn, AgentId) ->
  [{
    #agent_record{id = ?agent_record_id('$1', '$2', '_'), _ = '_'},
    [{'==', '$1', {const,Fqsn}}, {'==', '$2', {const,AgentId}}],
    ['$_']
  }].
