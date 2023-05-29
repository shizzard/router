-module(router_grpc_client).
-behaviour(gen_statem).

-include_lib("router_grpc/include/router_grpc.hrl").
-include_lib("router_grpc/include/router_grpc_client.hrl").
-include("router_grpc_service_registry.hrl").

-export([is_ready/1, await_ready/2, grpc_request/5, grpc_data/3, grpc_terminate/2]).
-export([start_link/1, start_link/2, init/1, callback_mode/0, handle_event/4]).

-record(caller, {
  pid :: pid(),
  stream_ref :: stream_ref(),
  mon_ref :: reference()
}).
-record(callers_index, {
  stream_ref_index = #{} :: #{stream_ref() => #caller{}},
  pid_index = #{} :: #{pid() => #caller{}}
}).

-record(state, {
  host :: grpc_host(),
  port :: grpc_port(),
  conn_pid :: pid() | undefined,
  callers_index = callers_index_new() :: #callers_index{}
}).
-type state() :: #state{}.

-type grpc_host() :: string().
-type grpc_port() :: 0..65535.
-type grpc_service() :: binary().
-type grpc_method() :: binary().
-type grpc_headers() :: #{binary() => binary()}.
-type stream_ref() :: reference().
-export_type([grpc_host/0, grpc_port/0, grpc_service/0, grpc_method/0, grpc_headers/0, stream_ref/0]).

%% FSM States

-define(fsm_state_on_init(), {fsm_state_on_init}).
-define(fsm_state_on_gun_connect(), {fsm_state_on_gun_connect}).
-define(fsm_state_on_gun_up(), {fsm_state_on_gun_up}).

-type fsm_state() :: ?fsm_state_on_init() | ?fsm_state_on_gun_connect() | ?fsm_state_on_gun_up().

%% Local messages

-define(msg_gun_up(ConnPid, Protocol),
  {gun_up, ConnPid, Protocol}).
-define(msg_gun_down(ConnPid, Protocol, Reason, KilledStreams, UnprocessedStreams),
  {gun_down, ConnPid, Protocol, Reason, KilledStreams, UnprocessedStreams}).
-define(msg_gun_upgrade(ConnPid, StreamRef, Protocols, Headers),
  {gun_upgrade, ConnPid, StreamRef, Protocols, Headers}).
-define(msg_gun_error(ConnPid, StreamRef, Reason),
  {gun_error, ConnPid, StreamRef, Reason}).
-define(msg_gun_error(ConnPid, Reason),
  {gun_error, ConnPid, Reason}).
-define(msg_gun_push(ConnPid, StreamRef, NewStreamRef, Method, URI, Headers),
  {gun_push, ConnPid, StreamRef, NewStreamRef, Method, URI, Headers}).
-define(msg_gun_inform(ConnPid, StreamRef, Status, Headers),
  {gun_inform, ConnPid, StreamRef, Status, Headers}).
-define(msg_gun_response(ConnPid, StreamRef, IsFin, Status, Headers),
  {gun_response, ConnPid, StreamRef, IsFin, Status, Headers}).
-define(msg_gun_data(ConnPid, StreamRef, IsFin, Data),
  {gun_data, ConnPid, StreamRef, IsFin, Data}).
-define(msg_gun_trailers(ConnPid, StreamRef, Trailers),
  {gun_trailers, ConnPid, StreamRef, Trailers}).

%% State transition messages

-define(msg_gun_connect(), {msg_gun_connect}).

%% Incoming calls messages

-define(msg_is_ready(), {msg_is_ready}).
-define(msg_grpc_request(CallerPid, Service, Method, Headers),
  {msg_grpc_request, CallerPid, Service, Method, Headers}).
-define(msg_grpc_data(StreamRef, Data),
  {msg_grpc_data, StreamRef, Data}).
-define(msg_grpc_terminate(StreamRef), {msg_grpc_terminate, StreamRef}).

-define(default_headers, #{
  ?http2_header_content_type => <<"application/grpc+proto">>,
  ?http2_header_te => <<"trailers">>,
  ?grpc_header_user_agent => <<"grpcc-erlang/0.1.0">>
}).

-define(connection_check_interval, 100).



%% Interface



-spec is_ready(Pid :: pid()) ->
  typr:generic_return(
    OkRet :: boolean(),
    ErrorRet :: term()
  ).

is_ready(Pid) ->
  gen_statem:call(Pid, ?msg_is_ready()).



-spec await_ready(Pid :: pid(), Timeout :: pos_integer()) ->
  typr:ok_return() | error.

await_ready(_ConnPid, N) when N =< 0 -> error;

await_ready(ConnPid, Timeout) ->
  case router_grpc_client:is_ready(ConnPid) of
    {error, _} -> error;
    {ok, true} -> ok;
    {ok, false} ->
      timer:sleep(?connection_check_interval),
      await_ready(ConnPid, Timeout - ?connection_check_interval)
  end.



-spec grpc_request(
  Pid :: pid(),
  CallerPid :: pid(),
  Service :: grpc_service(),
  Method :: grpc_method(),
  Headers :: grpc_headers()
) ->
  typr:generic_return(
    OkRet :: stream_ref(),
    ErrorRet :: term()
  ).

grpc_request(Pid, CallerPid, Service, Method, Headers) ->
  gen_statem:call(Pid, ?msg_grpc_request(CallerPid, Service, Method, Headers)).



-spec grpc_data(
  Pid :: pid(),
  StreamRef :: stream_ref(),
  Data :: binary()
) ->
  typr:generic_return(
    ErrorRet :: term()
  ).

grpc_data(Pid, StreamRef, Data) ->
  gen_statem:call(Pid, ?msg_grpc_data(StreamRef, Data)).



-spec grpc_terminate(
  Pid :: pid(),
  StreamRef :: stream_ref()
) ->
  typr:generic_return(
    ErrorRet :: term()
  ).

grpc_terminate(Pid, StreamRef) ->
  gen_statem:call(Pid, ?msg_grpc_terminate(StreamRef)).



-spec start_link(
  Host :: grpc_host(),
  Port :: grpc_port()
) ->
  typr:ok_return(OkRet :: pid()).

start_link(Host, Port) ->
  gen_statem:start_link(?MODULE, [Host, Port], []).



-spec start_link(
  Definition :: router_grpc:definition_external()
) ->
  typr:ok_return(OkRet :: pid()).

start_link(Definition) ->
  gen_statem:start_link(?MODULE, [Definition], []).



-spec init([term()]) ->
  {ok, FsmState :: fsm_state(), S0 :: state(), Action :: gen_statem:action()}.

init([Definition]) ->
  {ok, ?fsm_state_on_init(), #state{
    host = erlang:binary_to_list(Definition#router_grpc_service_registry_definition_external.host),
    port = Definition#router_grpc_service_registry_definition_external.port
  }, {next_event, state_timeout, ?msg_gun_connect()}};

init([Host, Port]) ->
  {ok, ?fsm_state_on_init(), #state{
    host = Host, port = Port
  }, {next_event, state_timeout, ?msg_gun_connect()}}.



-spec callback_mode() -> handle_event_function.

callback_mode() ->
  handle_event_function.



%% States



-spec handle_event(atom(), term(), atom(), state()) ->
  gen_statem:event_handler_result(FsmState :: fsm_state()).

%% Initial state; connect to remote server
handle_event(state_timeout, ?msg_gun_connect(), ?fsm_state_on_init(), S0) ->
  {ok, ConnPid} = gun:open(S0#state.host, S0#state.port, #{protocols => [http2], retry => 0, connect_timeout => 1000}),
  {next_state, ?fsm_state_on_gun_connect(), S0#state{conn_pid = ConnPid}};

%% Connection established; FSM operational
handle_event(info, ?msg_gun_up(ConnPid, http2), ?fsm_state_on_gun_connect(), #state{conn_pid = ConnPid} = S0) ->
  {next_state, ?fsm_state_on_gun_up(), S0};

%% Connection lost; notify clients and terminate
handle_event(
  info,
  ?msg_gun_down(ConnPid, http2, _Reason, KilledStreams, UnprocessedStreams),
  _State,
  #state{conn_pid = ConnPid, callers_index = CI}
) ->
  maps:foreach(fun(StreamRef, #caller{pid = Pid}) ->
    case lists:member(StreamRef, KilledStreams)  of
      true -> Pid ! ?grpc_event_stream_killed(StreamRef);
      false -> case lists:member(StreamRef, UnprocessedStreams) of
        true -> Pid ! ?grpc_event_stream_unprocessed(StreamRef);
        false -> Pid ! ?grpc_event_connection_down(StreamRef)
      end
    end
  end, CI#callers_index.stream_ref_index),
  {stop, disconnected};

%% Stream-level error; notify client, terminate and remove the stream and continue
handle_event(info, ?msg_gun_error(ConnPid, StreamRef, _Reason), _State, #state{
  conn_pid = ConnPid, callers_index = CI0
} = S0) ->
  case callers_index_get(StreamRef, CI0) of
    undefined -> keep_state_and_data;
    #caller{pid = Pid} ->
      Pid ! ?grpc_event_stream_killed(StreamRef),
      ok = gun:cancel(ConnPid, StreamRef),
      {keep_state, S0#state{callers_index = callers_index_remove(StreamRef, CI0)}}
  end;

%% Connection-level error; notify clients and terminate
handle_event(info, ?msg_gun_error(ConnPid, _Reason), _State, #state{conn_pid = ConnPid, callers_index = CI} = _S0) ->
  maps:foreach(fun(StreamRef, #caller{pid = Pid}) ->
    Pid ! ?grpc_event_connection_down(StreamRef)
  end, CI#callers_index.stream_ref_index),
  {stop, disconnected};

%% Response message; notify client, remove the stream if IsFin flag is set, and continue
handle_event(info, ?msg_gun_response(ConnPid, StreamRef, IsFin, Status, Headers), _State, #state{
  conn_pid = ConnPid, callers_index = CI0
} = S0) ->
  case callers_index_get(StreamRef, CI0) of
    undefined -> ok;
    #caller{pid = Pid} ->
      Pid ! ?grpc_event_response(StreamRef, IsFin, Status, Headers)
  end,
  if
    IsFin ->
      CI = callers_index_remove(StreamRef, CI0),
      {keep_state, S0#state{callers_index = CI}};
    true -> keep_state_and_data
  end;

%% Data message; notify client, remove the stream if IsFin flag is set, and continue
handle_event(info, ?msg_gun_data(ConnPid, StreamRef, IsFin, <<0:1/unsigned-integer-unit:8, Len:4/unsigned-integer-unit:8, Data:Len/binary-unit:8>>), _State, #state{
  conn_pid = ConnPid, callers_index = CI0
} = S0) ->
  case callers_index_get(StreamRef, CI0) of
    undefined -> ok;
    #caller{pid = Pid} ->
      Pid ! ?grpc_event_data(StreamRef, IsFin, Data)
  end,
  if
    IsFin ->
      CI = callers_index_remove(StreamRef, CI0),
      {keep_state, S0#state{callers_index = CI}};
    true -> keep_state_and_data
  end;

%% Trailers message; notify client, remove the stream and continue
handle_event(info, ?msg_gun_trailers(ConnPid, StreamRef, Trailers), _State, #state{
  conn_pid = ConnPid, callers_index = CI0
} = S0) ->
  case callers_index_get(StreamRef, CI0) of
    undefined -> ok;
    #caller{pid = Pid} ->
      Pid ! ?grpc_event_trailers(StreamRef, Trailers)
  end,
  {keep_state, S0};

%% is_ready call;
handle_event({call, From}, ?msg_is_ready(), ?fsm_state_on_gun_up() = _State, _S0) ->
  {keep_state_and_data, [{reply, From, {ok, true}}]};

handle_event({call, From}, ?msg_is_ready(), _State, _S0) ->
  {keep_state_and_data, [{reply, From, {ok, false}}]};

%% Request call; perform the remote call, update callers index and continue
handle_event({call, From}, ?msg_grpc_request(CallerPid, Service, Method, Headers), ?fsm_state_on_gun_up(), S0) ->
  StreamRef = gun:post(S0#state.conn_pid, <<"/", Service/binary, "/", Method/binary>>, maps:merge(?default_headers, Headers)),
  {keep_state, S0#state{
    callers_index = callers_index_set(StreamRef, CallerPid, S0#state.callers_index)
  }, [{reply, From, {ok, StreamRef}}]};

handle_event({call, From}, ?msg_grpc_request(_CallerPid, _Service, _Method, _Headers), _State, _S0) ->
  {keep_state_and_data, [{reply, From, {error, not_ready}}]};

handle_event({call, From}, ?msg_grpc_data(StreamRef, Data), _State, #state{conn_pid = ConnPid} = _S0) ->
  Len = erlang:byte_size(Data),
  Data1 = <<0:1/unsigned-integer-unit:8, Len:4/unsigned-integer-unit:8, Data:Len/binary-unit:8>>,
  ok = gun:data(ConnPid, StreamRef, nofin, Data1),
  {keep_state_and_data, [{reply, From, ok}]};

handle_event({call, From}, ?msg_grpc_terminate(StreamRef), _State, #state{
  conn_pid = ConnPid, callers_index = CI
} = S0) ->
  ok = gun:cancel(ConnPid, StreamRef),
  {keep_state, S0#state{
    callers_index = callers_index_remove(StreamRef, CI)
  }, [{reply, From, ok}]};

%% Ignore everything else; including msg_gun_upgrade, msg_gun_push, msg_gun_inform
handle_event(_EventType, _EventContent, _State, _S0) ->
  keep_state_and_data.



%% Internals



callers_index_new() -> #callers_index{}.



callers_index_set(StreamRef, Pid, #callers_index{stream_ref_index = SRI0, pid_index = PI0} = CI0) ->
  Caller = #caller{pid = Pid, stream_ref = StreamRef, mon_ref = erlang:monitor(process, Pid)},
  CI0#callers_index{stream_ref_index = SRI0#{StreamRef => Caller}, pid_index = PI0#{Pid => Caller}}.



callers_index_get(StreamRef, #callers_index{stream_ref_index = SRI0}) when is_reference(StreamRef) ->
  maps:get(StreamRef, SRI0, undefined);

callers_index_get(Pid, #callers_index{pid_index = PI0}) when is_pid(Pid) ->
  maps:get(Pid, PI0, undefined).



callers_index_remove(StreamRef, #callers_index{stream_ref_index = SRI0, pid_index = PI0} = CI0) when is_reference(StreamRef) ->
  case maps:take(StreamRef, SRI0) of
    error -> CI0;
    {#caller{pid = Pid, stream_ref = StreamRef, mon_ref = MonRef}, SRI} ->
      true = erlang:demonitor(MonRef, [flush]),
      PI = maps:remove(Pid, PI0),
      CI0#callers_index{stream_ref_index = SRI, pid_index = PI}
  end;

callers_index_remove(Pid, #callers_index{stream_ref_index = SRI0, pid_index = PI0} = CI0) when is_pid(Pid) ->
  case maps:take(Pid, PI0) of
    error -> CI0;
    {#caller{pid = Pid, stream_ref = StreamRef, mon_ref = MonRef}, PI} ->
      true = erlang:demonitor(MonRef, [flush]),
      SRI = maps:remove(StreamRef, SRI0),
      CI0#callers_index{stream_ref_index = SRI, pid_index = PI}
  end.
