-module(router_grpc_stream_h).
-behaviour(gen_server).

-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").

-export([lookup/1]).
-export([
  start_link/4, init/1,
  handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3
]).

-record(state, {
  session_id :: session_id(),
  host :: router_grpc_service_registry:endpoint_host(),
  port :: router_grpc_service_registry:endpoint_port(),
  conn_pid :: pid() | undefined,
  conn_monitor_ref :: reference() | undefined,
  session_inactivity_limit_ms :: pos_integer(),
  session_ref :: reference() | undefined,
  session_timer_ref :: reference() | undefined
}).
-type state() :: #state{}.

-type session_id() :: binary().
-export_type([session_id/0]).

-define(gproc_key(Id), {?MODULE, Id}).



%% Messages



-define(msg_session_inactivity_trigger(Ref), {msg_session_inactivity_trigger, Ref}).



%% Metrics



%% Interface



-spec lookup(SessionId :: session_id()) ->
  Ret :: pid() | undefined.

lookup(SessionId) -> gproc:where({n, l, ?gproc_key(SessionId)}).



-spec start_link(
  SessionId :: session_id(),
  Host :: router_grpc_service_registry:endpoint_host(),
  Port :: router_grpc_service_registry:endpoint_port(),
  ConnPid :: pid()
) ->
  typr:ok_return(OkRet :: pid()).

start_link(SessionId, Host, Port, ConnPid) ->
  gen_server:start_link(?MODULE, {SessionId, Host, Port, ConnPid}, []).



init({SessionId, Host, Port, ConnPid}) ->
  router_log:component(router_grpc),
  ok = quickrand:seed(),
  ok = init_prometheus_metrics(),
  {ok, Limit} = router_config:get(router_grpc, [session, inactivity_limit_ms]),
  S0 = #state{
    session_id = SessionId, host = Host, port = Port, conn_pid = ConnPid,
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
      {ok, S0#state{
        conn_monitor_ref = erlang:monitor(process, S0#state.conn_pid)
      }};
    Pid ->
      {error, {already_started, S0#state.session_id, Pid}}
  end.



%% Handlers



handle_call(Unexpected, _GenReplyTo, S0) ->
  ?l_error(#{text => "Unexpected call", what => handle_call, details => Unexpected}),
  {reply, badarg, S0}.



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


init_prometheus_metrics() ->
  ok.
