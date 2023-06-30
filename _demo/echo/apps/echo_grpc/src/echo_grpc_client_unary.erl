-module(echo_grpc_client_unary).
-behaviour(gen_statem).

-compile([nowarn_untyped_record]).

-include_lib("echo/include/registry_definitions.hrl").
-include_lib("echo_grpc/include/echo_grpc.hrl").
-include_lib("echo_grpc/include/echo_grpc_client.hrl").
-include_lib("echo_log/include/echo_log.hrl").

-export([request/7]).
-export([start_link/0, init/1, callback_mode/0, handle_event/4]).

-record(state, {
  stream_ref :: term(),
  from :: term(),
  definition :: atom(),
  reply_record :: atom(),
  status :: term(),
  headers :: term(),
  pdu :: term(),
  trailers :: term()
}).
-type state() :: #state{}.

-define(reply(Status, Headers, Pdu, Trailers), {Status, Headers, Pdu, Trailers}).


%% FSM States

-define(fsm_state_on_await_request(), {fsm_state_on_await_request}).
-define(fsm_state_on_await_response(), {fsm_state_on_await_response}).

%% External messages

-define(call_request(Fqsn, Method, Headers, Definition, Pdu, ReplyRecord), {call_request, Fqsn, Method, Headers, Definition, Pdu, ReplyRecord}).

%% Local messages

-define(msg_report_and_terminate(Reason), {msg_report_and_terminate, Reason}).

%% Termination reasons

-define(term_reason_credentials_exchange_error, credentials_exchange_error).
-define(term_reason_remote_term, remote_connection_terminated).
-define(term_reason_local_error, local_error).



%% Interface



-spec request(
  Pid :: pid(),
  Fqsn :: binary(),
  Method :: binary(),
  Headers :: map(),
  Definition :: atom(),
  Pdu :: term(),
  ReplyRecord :: atom()
) ->
  typr:generic_return(
    OkRet :: tuple(),
    ErrorRet :: term()
  ).

request(Pid, Fqsn, Method, Headers, Definition, Pdu, ReplyRecord) ->
  gen_statem:call(Pid, ?call_request(Fqsn, Method, Headers, Definition, Pdu, ReplyRecord)).



-spec start_link() ->
  typr:ok_return(OkRet :: pid()).

start_link() ->
  gen_statem:start_link({local, ?MODULE}, ?MODULE, {}, []).



-spec init({}) ->
  {ok, atom(), state(), tuple()}.

init({}) ->
  echo_log:component(echo_grpc_client),
  quickrand:seed(),
  {ok, ?fsm_state_on_await_request(), #state{}}.



-spec callback_mode() -> atom().

callback_mode() ->
  handle_event_function.



%% States



-spec handle_event(atom(), term(), atom(), state()) ->
  term().

%% Ranch handshake to get local connection socket
handle_event({call, From}, ?call_request(Fqsn, Method, Headers, Definition, Pdu, ReplyRecord), ?fsm_state_on_await_request(), S0) ->
  ok = echo_grpc_client:await_ready(whereis(echo_grpc_client), 500),
  {ok, StreamRef} = echo_grpc_client:grpc_request(whereis(echo_grpc_client), self(), Fqsn, Method, Headers),
  Data = Definition:encode_msg(Pdu),
  ok = echo_grpc_client:grpc_data(whereis(echo_grpc_client), StreamRef, _IsFin = true, Data),
  {next_state, ?fsm_state_on_await_response(), S0#state{stream_ref = StreamRef, definition = Definition, reply_record = ReplyRecord, from = From}};

handle_event(info, ?grpc_event_response(StreamRef, IsFin, Status, Headers), ?fsm_state_on_await_response(), #state{stream_ref = StreamRef} = S0) ->
  if
    IsFin ->
      {stop_and_reply, normal, {reply, S0#state.from, {ok, ?reply(Status, Headers, undefined, undefined)}}};
    true ->
      {keep_state, S0#state{status = Status, headers = Headers}}
  end;

handle_event(info, ?grpc_event_data(StreamRef, IsFin, Data), ?fsm_state_on_await_response(), #state{
  stream_ref = StreamRef, definition = Definition, reply_record = ReplyRecord
} = S0) ->
  Pdu = Definition:decode_msg(Data, ReplyRecord),
  if
    IsFin ->
      {stop_and_reply, normal, {reply, S0#state.from, {ok, ?reply(S0#state.status, S0#state.headers, Pdu, undefined)}}};
    true ->
      {keep_state, S0#state{pdu = Pdu}}
  end;

handle_event(info, ?grpc_event_trailers(StreamRef, Trailers), ?fsm_state_on_await_response(), #state{stream_ref = StreamRef} = S0) ->
  {stop_and_reply, normal, {reply, S0#state.from, {ok, ?reply(S0#state.status, S0#state.headers, S0#state.pdu, Trailers)}}};

%% Default handler, warn and drop
handle_event(EventType, EventContent, State, _S0) ->
  ?l_warning(#{
    text => "Unexpected event",
    what => event,
    details => #{fsm_state => State, event_type => EventType, event_content => EventContent}
  }),
  keep_state_and_data.
