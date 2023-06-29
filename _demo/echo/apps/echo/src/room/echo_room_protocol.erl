-module(echo_room_protocol).
-behaviour(gen_statem).

-include_lib("echo_log/include/echo_log.hrl").

-export([start_link/3, init/1, callback_mode/0, handle_event/4]).


-record(data_buffer, {
  dangling_data = <<>> :: binary(),
  sub_buffer = <<>> :: binary(),
  room_name = <<>> :: binary(),
  room_secret = <<>> :: binary(),
  display_name = <<>> :: binary()
}).

-record(state, {
  ref :: term(),
  socket :: gen_tcp:socket() | undefined,
  transport :: atom(),
  opts :: [term()],
  outbound_traffic = 0 :: non_neg_integer(),
  inbound_traffic = 0 :: non_neg_integer(),
  data_buffer = #data_buffer{} :: #data_buffer{},
  room_name = <<>> :: binary(),
  room_secret = <<>> :: binary(),
  display_name = <<>> :: binary(),
  join_ref :: erlang:reference(),
  ok_tag :: atom(),
  closed_tag :: atom(),
  error_tag :: atom(),
  passive_tag :: atom()
}).
-type state() :: #state{}.

-define(credentials_separator, <<"\n">>).

%% FSM States

-define(fsm_state_on_ranch_handshake(), {fsm_state_on_ranch_handshake}).
-define(fsm_state_on_credentials_exchange(), {fsm_state_on_credentials_exchange}).
-define(fsm_state_on_join_room(), {fsm_state_on_join_room}).
-define(fsm_state_on_maybe_send_dangling_data(), {fsm_state_on_maybe_send_dangling_data}).
-define(fsm_state_on_data_exchange(), {fsm_state_on_data_exchange}).
-define(fsm_state_on_terminate(), {fsm_state_on_terminate}).

%% Local messages

-define(msg_ranch_handshake(), {msg_ranch_handshake}).
-define(msg_join_room(), {msg_join_room}).
-define(msg_maybe_send_dangling_data(Data), {msg_maybe_send_dangling_data, Data}).
-define(msg_incoming_msg(Msg), {msg_incoming_msg, Msg}).

-define(msg_ok(Tag, Socket, Data), {Tag, Socket, Data}).
-define(msg_closed(Tag, Socket), {Tag, Socket}).
-define(msg_error(Tag, Socket, Reason), {Tag, Socket, Reason}).
-define(msg_passive(Tag, Socket), {Tag, Socket}).

-define(msg_report_and_terminate(Reason), {msg_report_and_terminate, Reason}).

%% Termination reasons

-define(term_reason_credentials_exchange_error, credentials_exchange_error).
-define(term_reason_remote_term, remote_connection_terminated).
-define(term_reason_local_error, local_error).



%% Interface



-spec start_link(Ref :: term(), Transport :: atom(), Opts :: term()) ->
  typr:ok_return(OkRet :: pid()).

start_link(Ref, Transport, Opts) ->
  gen_statem:start_link(?MODULE, {Ref, Transport, Opts}, []).



-spec init({Ref :: term(), Transport :: atom(), Opts :: term()}) ->
  {ok, atom(), state(), tuple()}.

init({Ref, Transport, Opts}) ->
  echo_log:component(echo_room),
  quickrand:seed(),
  {OkTag, ClosedTag, ErrorTag, PassiveTag} = Transport:messages(),
  {ok, ?fsm_state_on_ranch_handshake(), #state{
    ref = Ref, transport = Transport, opts = Opts,
    ok_tag = OkTag, closed_tag = ClosedTag, error_tag = ErrorTag, passive_tag = PassiveTag
  }, {state_timeout, 0, ?msg_ranch_handshake()}}.



-spec callback_mode() -> atom().

callback_mode() ->
  handle_event_function.


%% States



-spec handle_event(atom(), term(), atom(), state()) ->
  term().

%% Ranch handshake to get local connection socket
handle_event(state_timeout, ?msg_ranch_handshake(), ?fsm_state_on_ranch_handshake(), S0) ->
  {ok, Socket} = ranch:handshake(S0#state.ref),
  ok = (S0#state.transport):setopts(Socket, [{active, once}]),
  {next_state, ?fsm_state_on_credentials_exchange(), S0#state{socket = Socket}};

%% Reading credentials
handle_event(info, ?msg_ok(Tag, Socket, Data), ?fsm_state_on_credentials_exchange(), #state{ok_tag = Tag, socket = Socket} = S0) ->
  case handle_event_parse_credentials_exchange(Data, S0#state.data_buffer) of
    {ok, Db} ->
      ?l_debug(#{text => "Data buffer parsed", result => ok, details => #{room_name => Db#data_buffer.room_name, room_secret => Db#data_buffer.room_secret}}),
      {next_state, ?fsm_state_on_join_room(), S0#state{data_buffer = Db}, {state_timeout, 0, ?msg_join_room()}};
    {more, Db} ->
      {keep_state, active_once(S0#state{data_buffer = Db})};
    {error, Reason} ->
      ?l_error(#{text => "Local connection error", result => error, details => #{reason => Reason}}),
      {next_state, ?fsm_state_on_terminate(), S0, {state_timeout, 0, ?msg_report_and_terminate(?term_reason_credentials_exchange_error)}}
  end;

%% Joining the room
handle_event(state_timeout, ?msg_join_room(), ?fsm_state_on_join_room(), #state{data_buffer = Db} = S0) ->
  Self = self(),
  case echo_room:join(
    Db#data_buffer.room_name,
    Db#data_buffer.room_secret,
    Db#data_buffer.display_name,
    fun(Msg) -> gen_statem:cast(Self, ?msg_incoming_msg(Msg)) end
  ) of
    {ok, JoinRef} ->
      ?l_debug(#{text => "Joined room", result => ok, details => #{room_name => Db#data_buffer.room_name, display_name => Db#data_buffer.display_name}}),
      {next_state, ?fsm_state_on_maybe_send_dangling_data(), S0#state{
        room_name = Db#data_buffer.room_name,
        room_secret = Db#data_buffer.room_secret,
        display_name = Db#data_buffer.display_name,
        join_ref = JoinRef,
        data_buffer = #data_buffer{}
      }, {state_timeout, 0, ?msg_maybe_send_dangling_data(Db#data_buffer.dangling_data)}};
    {error, Reason} ->
      ?l_debug(#{text => "Failed to join room", result => error, details => #{reason => Reason}}),
      {next_state, ?fsm_state_on_terminate(), S0, {state_timeout, 0, ?msg_report_and_terminate(?term_reason_credentials_exchange_error)}}
  end;

handle_event(state_timeout, ?msg_maybe_send_dangling_data(<<>>), ?fsm_state_on_maybe_send_dangling_data(), #state{} = S0) ->
  ?l_debug(#{text => "No dangling data found"}),
  {next_state, ?fsm_state_on_data_exchange(), active_once(S0)};

handle_event(state_timeout, ?msg_maybe_send_dangling_data(Data), ?fsm_state_on_maybe_send_dangling_data(), #state{
  room_name = RoomName,
  join_ref = JoinRef
} = S0) ->
  ?l_debug(#{text => "Sending dangling data", details => #{data => Data}}),
  ok = echo_room:send(RoomName, JoinRef, Data),
  {next_state, ?fsm_state_on_data_exchange(), active_once(S0)};

handle_event(info, ?msg_ok(Tag, Socket, Data), ?fsm_state_on_data_exchange(), #state{
  ok_tag = Tag, socket = Socket,
  room_name = RoomName, join_ref = JoinRef
} = S0) ->
  ?l_debug(#{text => "Data pass fwd", details => #{data => Data}}),
  ok = echo_room:send(RoomName, JoinRef, Data),
  {keep_state, active_once(S0)};

handle_event(cast, ?msg_incoming_msg(Data), ?fsm_state_on_data_exchange(), S0) ->
  ?l_debug(#{text => "Data pass bck", details => #{data => Data}}),
  case (S0#state.transport):send(S0#state.socket, Data) of
    ok ->
      {keep_state, S0};
    {error, Reason} ->
      ?l_debug(#{text => "Failed to pass data bck", result => error, details => #{reason => Reason}}),
      {next_state, ?fsm_state_on_terminate(), S0, {state_timeout, 0, ?msg_report_and_terminate(?term_reason_local_error)}}
  end;

% %% Remote party closed connection
handle_event(_, ?msg_closed(Tag, Socket), _AnyState, #state{closed_tag = Tag, socket = Socket} = S0) ->
  {next_state, ?fsm_state_on_terminate(), S0, {state_timeout, 0, ?msg_report_and_terminate(?term_reason_remote_term)}};

handle_event(state_timeout, ?msg_report_and_terminate(Reason), ?fsm_state_on_terminate(), #state{outbound_traffic = OT, inbound_traffic = IT} = S0) ->
  ?l_debug(#{text => "Connection terminating", result => ok, details => #{reason => Reason, inbound_traffic => IT, outbound_traffic => OT, total_traffic => IT + OT}}),
  {stop, normal, S0};

%% Default handler, warn and drop
handle_event(EventType, EventContent, State, _S0) ->
  ?l_warning(#{
    text => "Unexpected event",
    what => event,
    details => #{fsm_state => State, event_type => EventType, event_content => EventContent}
  }),
  keep_state_and_data.



%% Internals



%% Credentials are passed as an ASCII string "<room_name>\n<room_secret>\n"

handle_event_parse_credentials_exchange(<<>>, Db) ->
  {more, Db};

handle_event_parse_credentials_exchange(<<"\n", _Data/binary>>, #data_buffer{sub_buffer = <<>>}) ->
  {error, {invalid_credentials, sub_buffer_empty}};

handle_event_parse_credentials_exchange(<<"\n", Data/binary>>, #data_buffer{
  sub_buffer = SubBuffer,
  room_name = <<>>
} = Db) ->
  handle_event_parse_credentials_exchange(Data, Db#data_buffer{sub_buffer = <<>>, room_name = SubBuffer});

handle_event_parse_credentials_exchange(<<"\n", Data/binary>>, #data_buffer{
  sub_buffer = SubBuffer,
  room_secret = <<>>
} = Db) ->
  handle_event_parse_credentials_exchange(Data, Db#data_buffer{sub_buffer = <<>>, room_secret = SubBuffer});

handle_event_parse_credentials_exchange(<<"\n", Data/binary>>, #data_buffer{
  sub_buffer = SubBuffer,
  display_name = <<>>
} = Db) ->
  {ok, Db#data_buffer{dangling_data = Data, sub_buffer = <<>>, display_name = SubBuffer}};

handle_event_parse_credentials_exchange(<<Byte:1/binary, Data/binary>>, #data_buffer{
  sub_buffer = SubBuffer
} = Db) ->
  handle_event_parse_credentials_exchange(Data, Db#data_buffer{sub_buffer = <<SubBuffer/binary, Byte/binary>>}).



active_once(S0) ->
  ok = (S0#state.transport):setopts(S0#state.socket, [{active, once}]),
  S0.
