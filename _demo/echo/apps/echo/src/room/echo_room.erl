-module(echo_room).
-behaviour(gen_server).

-compile([nowarn_untyped_record]).

-include_lib("echo_log/include/echo_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").

-export([pid/1, join/4, send/3, get_stats/1]).
-export([start_link/2, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).


-record(participant, {
  display_name :: binary(),
  push_fun :: fun((Msg :: binary()) -> ok)
}).

-record(state, {
  name :: binary(),
  secret :: binary(),
  participants = #{} :: #{erlang:reference() => #participant{}}
}).
-type state() :: #state{}.

-define(echo_room_gproc_key(Name), {echo_room_gproc_key, Name}).



%% Messages



-define(msg_join(Secret, DisplayName, PushFun), {msg_join, Secret, DisplayName, PushFun}).
-define(msg_send(JoinRef, Msg), {msg_send, JoinRef, Msg}).
-define(msg_get_stats(), {msg_get_stats}).



%% Metrics



%% Interface



-spec pid(Name :: binary()) ->
  Ret :: pid() | undefined.

pid(Name) ->
  gproc:where({n, l, ?echo_room_gproc_key(Name)}).



-spec join(
  Name :: binary(),
  Secret :: binary(),
  DisplayName :: binary(),
  PushFun :: fun((Msg :: binary()) -> ok)
) ->
  typr:generic_return(
    OkRet :: erlang:reference(),
    ErrorRet :: term()
  ).

join(Name, Secret, DisplayName, PushFun) ->
  maybe_call(Name, ?msg_join(Secret, DisplayName, PushFun)).



-spec send(
  Name :: binary(),
  JoinRef :: erlang:reference(),
  Msg :: binary()
) ->
  typr:generic_return(
    ErrorRet :: term()
  ).

send(Name, JoinRef, Msg) ->
  maybe_call(Name, ?msg_send(JoinRef, Msg)).



-spec get_stats(Name :: binary()) ->
  typr:generic_return(
    OkRet :: map(),
    ErrorRet :: term()
  ).

get_stats(Name) ->
  maybe_call(Name, ?msg_get_stats()).



-spec start_link(Name :: binary(), Secret :: binary()) ->
  typr:ok_return(OkRet :: pid()).

start_link(Name, Secret) ->
  gen_server:start_link(?MODULE, {Name, Secret}, []).



init({Name, Secret}) ->
  echo_log:component(echo_room),
  ok = quickrand:seed(),
  true = gproc:reg({n, l, ?echo_room_gproc_key(Name)}),
  ok = echo_grpc_client_control_stream:register_agent(Name, Name),
  S0 = #state{name = Name, secret = Secret},
  {ok, S0}.



%% Handlers



handle_call(?msg_join(Secret, DisplayName, PushFun), _GenReplyTo, #state{secret = Secret, participants = Participants} = S0) ->
  ParticipantRef = erlang:make_ref(),
  Participant = #participant{display_name = DisplayName, push_fun = PushFun},
  S1 = S0#state{participants = Participants#{ParticipantRef => Participant}},
  ok = fanout(DisplayName, <<"*joined*\n">>, Participants),
  {reply, {ok, ParticipantRef}, S1};

handle_call(?msg_join(Secret, DisplayName, _PushFun), _GenReplyTo, #state{secret = ActualSecret} = S0) ->
  ?l_debug(#{text => "Join room failed: invalid secret", result => error, details => #{
    display_name => DisplayName, provided_secret => Secret, actual_secret => ActualSecret
  }}),
  {reply, {error, invalid_secret}, S0};

handle_call(?msg_send(JoinRef, Msg), _GenReplyTo, #state{participants = Participants} = S0) ->
  case maps:get(JoinRef, Participants, undefined) of
    undefined ->
      {reply, {error, invalid_join_ref}, S0};
    #participant{display_name = DisplayName} ->
      ok = fanout(DisplayName, Msg, Participants),
      {reply, ok, S0}
  end;

handle_call(?msg_get_stats(), _GenReplyTo, #state{participants = Participants} = S0) ->
  {reply, {ok, #{participants_n => maps:size(Participants)}}, S0};

handle_call(Unexpected, _GenReplyTo, S0) ->
  ?l_error(#{text => "Unexpected call", what => handle_call, details => Unexpected}),
  {reply, badarg, S0}.



handle_cast(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected cast", what => handle_cast, details => Unexpected}),
  {noreply, S0}.



handle_info(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected info", what => handle_info, details => Unexpected}),
  {noreply, S0}.



terminate(_Reason, _S0) ->
  ok.



code_change(_OldVsn, S0, _Extra) ->
  {ok, S0}.



%% Internals



maybe_call(Name, Msg) ->
  case pid(Name) of
    undefined -> {error, invalid_room};
    Pid -> gen_server:call(Pid, Msg)
  end.



fanout(DisplayName, Msg, Participants) ->
  FanoutMsg = <<DisplayName/binary, ": ", Msg/binary>>,
  maps:foreach(fun(_, #participant{push_fun = PushFun}) ->
    PushFun(FanoutMsg)
  end, Participants).
