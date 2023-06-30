-module(rtgw_tunnel_protocol).
-behaviour(gen_statem).

-include_lib("rtgw/include/rtgw_tunnel.hrl").
-include_lib("rtgw_log/include/rtgw_log.hrl").

-export([start_link/3, init/1, callback_mode/0, handle_event/4]).


-record(data_buffer, {
  dangling_data = <<>> :: binary(),
  sub_buffer = <<>> :: binary(),
  tunnel_name = <<>> :: binary(),
  tunnel_secret = <<>> :: binary(),
  display_name = <<>> :: binary()
}).

-record(state, {
  ref :: term(),
  socket :: gen_tcp:socket() | undefined,
  upstream_socket :: gen_tcp:socket() | undefined,
  transport :: atom(),
  opts :: [term()],
  outbound_traffic = 0 :: non_neg_integer(),
  inbound_traffic = 0 :: non_neg_integer(),
  data_buffer = #data_buffer{} :: #data_buffer{},
  tunnel_name = <<>> :: binary(),
  tunnel_secret = <<>> :: binary(),
  display_name = <<>> :: binary(),
  tunnel :: #tunnel{},
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
-define(fsm_state_on_check_tunnel(), {fsm_state_on_check_tunnel}).
-define(fsm_state_on_connect_upstream(), {fsm_state_on_connect_upstream}).
-define(fsm_state_on_send_credentials(), {fsm_state_on_send_credentials}).
-define(fsm_state_on_maybe_send_dangling_data(), {fsm_state_on_maybe_send_dangling_data}).
-define(fsm_state_on_full_duplex(), {fsm_state_on_full_duplex}).
-define(fsm_state_on_terminate(), {fsm_state_on_terminate}).

%% Local messages

-define(msg_ranch_handshake(), {msg_ranch_handshake}).
-define(msg_check_tunnel(), {msg_check_tunnel}).
-define(msg_connect_upstream(), {msg_connect_upstream}).
-define(msg_send_credentials(), {msg_send_credentials}).
-define(msg_maybe_send_dangling_data(Data), {msg_maybe_send_dangling_data, Data}).
-define(msg_incoming_msg(Msg), {msg_incoming_msg, Msg}).

-define(msg_ok(Tag, Socket, Data), {Tag, Socket, Data}).
-define(msg_closed(Tag, Socket), {Tag, Socket}).
-define(msg_error(Tag, Socket, Reason), {Tag, Socket, Reason}).
-define(msg_passive(Tag, Socket), {Tag, Socket}).

-define(msg_report_and_terminate(Reason), {msg_report_and_terminate, Reason}).

%% Termination reasons

-define(term_reason_credentials_exchange_error, credentials_exchange_error).
-define(term_reason_invalid_tunnel, invalid_tunnel).
-define(term_reason_invalid_secret, invalid_secret).
-define(term_reason_upstream_inaccessible, upstream_inaccessible).
-define(term_reason_upstream_term, upstream_connection_terminated).
-define(term_reason_downstream_term, downstream_connection_terminated).



%% Interface



-spec start_link(Ref :: term(), Transport :: atom(), Opts :: term()) ->
  typr:ok_return(OkRet :: pid()).

start_link(Ref, Transport, Opts) ->
  gen_statem:start_link(?MODULE, {Ref, Transport, Opts}, []).



-spec init({Ref :: term(), Transport :: atom(), Opts :: term()}) ->
  {ok, atom(), state(), tuple()}.

init({Ref, Transport, Opts}) ->
  rtgw_log:component(rtgw_tunnel),
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
      ?l_debug(#{text => "Data buffer parsed", result => ok, details => #{tunnel_name => Db#data_buffer.tunnel_name, tunnel_secret => Db#data_buffer.tunnel_secret}}),
      {next_state, ?fsm_state_on_check_tunnel(), S0#state{data_buffer = Db}, {state_timeout, 0, ?msg_check_tunnel()}};
    {more, Db} ->
      {keep_state, active_once(S0#state{data_buffer = Db})};
    {error, Reason} ->
      ?l_error(#{text => "Local connection error", result => error, details => #{reason => Reason}}),
      {next_state, ?fsm_state_on_terminate(), S0, {state_timeout, 0, ?msg_report_and_terminate(?term_reason_credentials_exchange_error)}}
  end;

%% Joining the tunnel
handle_event(state_timeout, ?msg_check_tunnel(), ?fsm_state_on_check_tunnel(), #state{data_buffer = Db} = S0) ->
  case rtgw_tunnel_registry:lookup(Db#data_buffer.tunnel_name) of
    {ok, #tunnel{secret = Secret} = Tunnel} when Secret == Db#data_buffer.tunnel_secret ->
      ?l_debug(#{text => "Tunnel exists", result => ok, details => #{tunnel_name => Db#data_buffer.tunnel_name, display_name => Db#data_buffer.display_name}}),
      {next_state, ?fsm_state_on_connect_upstream(), S0#state{
        tunnel_name = Db#data_buffer.tunnel_name,
        tunnel_secret = Db#data_buffer.tunnel_secret,
        display_name = Db#data_buffer.display_name,
        tunnel = Tunnel
      }, {state_timeout, 0, ?msg_connect_upstream()}};
    {ok, _Tunnel} ->
      ?l_debug(#{text => "Invalid tunnel secret provided", result => error, details => #{
        tunnel_name => Db#data_buffer.tunnel_name, display_name => Db#data_buffer.display_name
      }}),
      {next_state, ?fsm_state_on_terminate(), S0, {state_timeout, 0, ?msg_report_and_terminate(?term_reason_invalid_secret)}};
    {error, Reason} ->
      ?l_debug(#{text => "Failed to lookup tunnel", result => error, details => #{
        reason => Reason, tunnel_name => Db#data_buffer.tunnel_name, display_name => Db#data_buffer.display_name
      }}),
      {next_state, ?fsm_state_on_terminate(), S0, {state_timeout, 0, ?msg_report_and_terminate(?term_reason_invalid_tunnel)}}
  end;

handle_event(state_timeout, ?msg_connect_upstream(), ?fsm_state_on_connect_upstream(), #state{
  tunnel = #tunnel{host = Host, port = Port}, data_buffer = Db
} = S0) ->
  case gen_tcp:connect(binary_to_list(Host), Port, [binary, {packet, 0}, {active, false}]) of
    {ok, Socket} ->
      ?l_debug(#{text => "Upstream connected", result => ok,
        details => #{tunnel_name => Db#data_buffer.tunnel_name, display_name => Db#data_buffer.display_name}}),
      {next_state, ?fsm_state_on_send_credentials(), S0#state{upstream_socket = Socket}, {state_timeout, 0, ?msg_send_credentials()}};
    {error, Reason} ->
      ?l_error(#{text => "Cannot connect to upstream", result => error, details => #{
        reason => Reason, details => #{tunnel_name => Db#data_buffer.tunnel_name, display_name => Db#data_buffer.display_name}
      }}),
      {next_state, ?fsm_state_on_terminate(), S0, {state_timeout, 0, ?msg_report_and_terminate(?term_reason_upstream_inaccessible)}}
  end;

handle_event(state_timeout, ?msg_send_credentials(), ?fsm_state_on_send_credentials(), #state{
  upstream_socket = Socket, tunnel_name = TunnelName, tunnel_secret = TunnelSecret, display_name = DisplayName,
  data_buffer = Db
} = S0) ->
  Data = <<TunnelName/binary, "\n", TunnelSecret/binary, "\n", DisplayName/binary, "\n">>,
  case gen_tcp:send(Socket, Data) of
    ok ->
      rtgw_tunnel_registry:add_traffic(TunnelName, in, erlang:byte_size(Data)),
      {next_state, ?fsm_state_on_maybe_send_dangling_data(), S0#state{data_buffer = #data_buffer{}}, {state_timeout, 0, ?msg_maybe_send_dangling_data(Db#data_buffer.dangling_data)}};
    {error, Reason} ->
      ?l_error(#{text => "Failed to send credentials", result => error, details => #{reason => Reason}}),
      {next_state, ?fsm_state_on_terminate(), S0, {state_timeout, 0, ?msg_report_and_terminate(?term_reason_upstream_inaccessible)}}
  end;

handle_event(state_timeout, ?msg_maybe_send_dangling_data(<<>>), ?fsm_state_on_maybe_send_dangling_data(), #state{} = S0) ->
  ?l_debug(#{text => "No dangling data found"}),
  {next_state, ?fsm_state_on_full_duplex(), upstream_active_once(active_once(S0))};

handle_event(state_timeout, ?msg_maybe_send_dangling_data(Data), ?fsm_state_on_maybe_send_dangling_data(), #state{
  upstream_socket = Socket, tunnel_name = TunnelName
} = S0) ->
  ?l_debug(#{text => "Sending dangling data", details => #{data => Data}}),
  ok = gen_tcp:send(Socket, Data),
  rtgw_tunnel_registry:add_traffic(TunnelName, in, erlang:byte_size(Data)),
  {next_state, ?fsm_state_on_full_duplex(), upstream_active_once(active_once(S0))};

handle_event(info, ?msg_ok(Tag, Socket, Data), ?fsm_state_on_full_duplex(), #state{
  ok_tag = Tag, socket = Socket, upstream_socket = USocket, tunnel_name = TunnelName
} = S0) ->
  ?l_debug(#{text => "Data pass fwd", details => #{data => Data}}),
  case gen_tcp:send(USocket, Data) of
    ok ->
      rtgw_tunnel_registry:add_traffic(TunnelName, in, erlang:byte_size(Data)),
      {keep_state, active_once(S0)};
    {error, Reason} ->
      ?l_debug(#{text => "Failed to send data upstream", result => error, details => #{reason => Reason}}),
      {next_state, ?fsm_state_on_terminate(), S0, {state_timeout, 0, ?msg_report_and_terminate(?term_reason_downstream_term)}}
  end;

handle_event(info, ?msg_ok(tcp, USocket, Data), ?fsm_state_on_full_duplex(), #state{
  socket = Socket, upstream_socket = USocket, tunnel_name = TunnelName
} = S0) ->
  ?l_debug(#{text => "Data pass bck", details => #{data => Data}}),
  case (S0#state.transport):send(Socket, Data) of
    ok ->
      rtgw_tunnel_registry:add_traffic(TunnelName, out, erlang:byte_size(Data)),
      {keep_state, upstream_active_once(S0)};
    {error, Reason} ->
      ?l_error(#{text => "Failed to send data downstream", result => error, details => #{reason => Reason}}),
      {next_state, ?fsm_state_on_terminate(), S0, {state_timeout, 0, ?msg_report_and_terminate(?term_reason_downstream_term)}}
  end;

% %% Downstream party closed connection
handle_event(_, ?msg_closed(Tag, Socket), _AnyState, #state{closed_tag = Tag, socket = Socket} = S0) ->
  {next_state, ?fsm_state_on_terminate(), S0, {state_timeout, 0, ?msg_report_and_terminate(?term_reason_downstream_term)}};

% %% Upstream party closed connection
handle_event(_, ?msg_closed(tcp, Socket), _AnyState, #state{upstream_socket = Socket} = S0) ->
  {next_state, ?fsm_state_on_terminate(), S0, {state_timeout, 0, ?msg_report_and_terminate(?term_reason_upstream_term)}};

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



%% Credentials are passed as an ASCII string "<tunnel_name>\n<tunnel_secret>\n"

handle_event_parse_credentials_exchange(<<>>, Db) ->
  {more, Db};

handle_event_parse_credentials_exchange(<<"\n", _Data/binary>>, #data_buffer{sub_buffer = <<>>}) ->
  {error, {invalid_credentials, sub_buffer_empty}};

handle_event_parse_credentials_exchange(<<"\n", Data/binary>>, #data_buffer{
  sub_buffer = SubBuffer,
  tunnel_name = <<>>
} = Db) ->
  handle_event_parse_credentials_exchange(Data, Db#data_buffer{sub_buffer = <<>>, tunnel_name = SubBuffer});

handle_event_parse_credentials_exchange(<<"\n", Data/binary>>, #data_buffer{
  sub_buffer = SubBuffer,
  tunnel_secret = <<>>
} = Db) ->
  handle_event_parse_credentials_exchange(Data, Db#data_buffer{sub_buffer = <<>>, tunnel_secret = SubBuffer});

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

upstream_active_once(S0) ->
  ok = inet:setopts(S0#state.upstream_socket, [{active, once}]),
  S0.
