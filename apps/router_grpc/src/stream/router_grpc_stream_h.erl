-module(router_grpc_stream_h).
-behaviour(gen_server).

-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").

-export([]).
-export([
  start_link/2, init/1,
  handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3
]).

-record(state, {
  id :: id(),
  conn_pid :: pid() | undefined,
  conn_monitor_ref :: reference() | undefined,
  session_ref :: reference() | undefined,
  session_timer_ref :: reference() | undefined
}).
-type state() :: #state{}.

-type id() :: binary().
-export_type([id/0]).

-define(gproc_key(Id), {?MODULE, Id}).

-define(session_inactivity_limit_ms, 15_000).



%% Messages



-define(msg_session_inactivity_trigger(Ref), {msg_session_inactivity_trigger, Ref}).



%% Metrics



%% Interface



-spec start_link(StreamId :: id(), ConnPid :: pid()) ->
  typr:ok_return(OkRet :: pid()).

start_link(StreamId, ConnPid) ->
  gen_server:start_link(?MODULE, {StreamId, ConnPid}, []).



init({StreamId, ConnPid}) ->
  router_log:component(router_grpc),
  ok = quickrand:seed(),
  ok = init_prometheus_metrics(),
  S0 = #state{},
  case init_register(StreamId, ConnPid, S0) of
    {ok, S1} ->
      ?l_debug(#{
        text => "gRPC stream handler registered", what => init,
        result => ok, details => #{stream_id => StreamId, conn_pid => ConnPid}
      }),
      {ok, S1};
    {error, Reason} ->
      ?l_warning(#{
        text => "Failed to register gRPC stream handler", what => init,
        result => error, details => #{reason => Reason}
      }),
      ignore
  end.



init_register(StreamId, ConnPid, S0) ->
  case gproc:where({n, l, ?gproc_key(StreamId)}) of
    undefined ->
      true = gproc:reg({n, l, ?gproc_key(StreamId)}),
      {ok, S0#state{
        id = StreamId,
        conn_pid = ConnPid,
        conn_monitor_ref = erlang:monitor(process, ConnPid)
      }};
    Pid ->
      {error, {already_started, StreamId, Pid}}
  end.



%% Handlers



handle_call(Unexpected, _GenReplyTo, S0) ->
  ?l_error(#{text => "Unexpected call", what => handle_call, details => Unexpected}),
  {reply, badarg, S0}.



handle_cast(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected cast", what => handle_cast, details => Unexpected}),
  {noreply, S0}.



handle_info(?msg_session_inactivity_trigger(Ref), #state{session_ref = Ref} = S0) ->
  ?l_debug(#{
    text => "Stream session expired", what => handle_info,
    details => #{stream_id => S0#state.id, inactivity_limit_ms => ?session_inactivity_limit_ms}
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
  session_ref = undefined,
  session_timer_ref = undefined
} = S0) ->
  Ref = erlang:make_ref(),
  TRef = erlang:send_after(?session_inactivity_limit_ms, self(), ?msg_session_inactivity_trigger(Ref)),
  {ok, S0#state{session_ref = Ref, session_timer_ref = TRef}};

init_session_timer(#state{
  session_timer_ref = OldTref
} = S0) ->
  ok = erlang:cancel_timer(OldTref),
  init_session_timer(S0#state{session_ref = undefined, session_timer_ref = undefined}).


init_prometheus_metrics() ->
  ok.
