-module(echo_grpc_client_control_stream).
-behaviour(gen_statem).

-compile([nowarn_untyped_record]).

-include_lib("echo/include/registry_definitions.hrl").
-include_lib("echo_grpc/include/echo_grpc.hrl").
-include_lib("echo_grpc/include/echo_grpc_client.hrl").
-include_lib("echo_log/include/echo_log.hrl").

-export([register_agent/2]).
-export([start_link/0, init/1, callback_mode/0, handle_event/4]).

-record(state, {
  stream_ref :: term(),
  session_id :: binary(),
  agent_id :: binary(),
  from :: term() | undefined
}).
-type state() :: #state{}.



%% FSM States

-define(fsm_state_on_declare_stateless_services(), {fsm_state_on_declare_stateless_services}).
-define(fsm_state_on_init_control_stream(), {fsm_state_on_init_control_stream}).
-define(fsm_state_on_operational(), {fsm_state_on_operational}).

%% Local messages

-define(msg_declare_stateless_services(), {msg_declare_stateless_services}).
-define(msg_init_control_stream(), {msg_init_control_stream}).
-define(msg_register_agent(AgentId, AgentInstance), {msg_register_agent, AgentId, AgentInstance}).

-define(msg_report_and_terminate(Reason), {msg_report_and_terminate, Reason}).

%% Termination reasons

-define(term_reason_credentials_exchange_error, credentials_exchange_error).
-define(term_reason_remote_term, remote_connection_terminated).
-define(term_reason_local_error, local_error).



%% Interface



-spec register_agent(AgentId :: binary(), AgentInstance :: binary() | undefined) ->
  typr:generic_return(ErrorRet :: term()).

register_agent(AgentId, AgentInstance) ->
  gen_statem:call(?MODULE, ?msg_register_agent(AgentId, AgentInstance)).



-spec start_link() ->
  typr:ok_return(OkRet :: pid()).

start_link() ->
  gen_statem:start_link({local, ?MODULE}, ?MODULE, {}, []).



-spec init({}) ->
  {ok, atom(), state(), tuple()}.

init({}) ->
  echo_log:component(echo_grpc_client),
  quickrand:seed(),
  {ok, ?fsm_state_on_declare_stateless_services(), #state{}, {state_timeout, 0, ?msg_declare_stateless_services()}}.



-spec callback_mode() -> atom().

callback_mode() ->
  handle_event_function.



%% States



-spec handle_event(atom(), term(), atom(), state()) ->
  term().

%% Ranch handshake to get local connection socket
handle_event(state_timeout, ?msg_declare_stateless_services(), ?fsm_state_on_declare_stateless_services(), S0) ->
  Host = <<"localhost">>,
  {ok, Port} = echo_config:get(echo_grpc, [listener, port]),
  ok = echo_grpc_client:await_ready(whereis(echo_grpc_client), 500),
  {ok, StreamRef} = echo_grpc_client:grpc_request(
    whereis(echo_grpc_client), self(), <<"lg.service.router.RegistryService">>, <<"RegisterVirtualService">>, #{}
  ),
  Pdu = #'lg.service.router.RegisterVirtualServiceRq'{
    virtual_service = #'lg.core.grpc.VirtualService'{
      service = {stateless, #'lg.core.grpc.VirtualService.StatelessVirtualService'{
        package = <<"lg.service.demo.echo">>,
        name = <<"LobbyService">>,
        methods = [
          #'lg.core.grpc.VirtualService.Method'{name = <<"SpawnRoom">>}
        ]
      }},
      endpoint = #'lg.core.network.Endpoint'{host = Host, port = Port}
    }
  },
  Data = registry_definitions:encode_msg(Pdu),
  ok = echo_grpc_client:grpc_data(whereis(echo_grpc_client), StreamRef, _IsFin = true, Data),
  {keep_state, S0#state{stream_ref = StreamRef}};

handle_event(info, ?grpc_event_response(StreamRef, _IsFin, _Status, _Headers), ?fsm_state_on_declare_stateless_services(), #state{
  stream_ref = StreamRef
} = _S0) ->
  keep_state_and_data;

handle_event(info, ?grpc_event_data(StreamRef, _IsFin, Data), ?fsm_state_on_declare_stateless_services(), #state{
  stream_ref = StreamRef
} = _S0) ->
  #'lg.service.router.RegisterVirtualServiceRs'{} = registry_definitions:decode_msg(Data, 'lg.service.router.RegisterVirtualServiceRs'),
  keep_state_and_data;

handle_event(info, ?grpc_event_trailers(StreamRef, _Trailers), ?fsm_state_on_declare_stateless_services(), #state{
  stream_ref = StreamRef
} = S0) ->
  {next_state, ?fsm_state_on_init_control_stream(), S0#state{stream_ref = undefined}, {state_timeout, 0, ?msg_init_control_stream()}};

handle_event(state_timeout, ?msg_init_control_stream(), ?fsm_state_on_init_control_stream(), S0) ->
  Host = <<"localhost">>,
  {ok, Port} = echo_config:get(echo_grpc, [listener, port]),
  ok = echo_grpc_client:await_ready(whereis(echo_grpc_client), 500),
  {ok, StreamRef} = echo_grpc_client:grpc_request(
    whereis(echo_grpc_client), self(), <<"lg.service.router.RegistryService">>, <<"ControlStream">>, #{}
  ),
  Pdu = #'lg.service.router.ControlStreamEvent'{
    id = #'lg.core.trait.Id'{tag = <<"init_rq">>},
    event = {init_rq, #'lg.service.router.ControlStreamEvent.InitRq'{
      virtual_service = #'lg.core.grpc.VirtualService'{
        service = {stateful, #'lg.core.grpc.VirtualService.StatefulVirtualService'{
          package = <<"lg.service.demo.echo">>,
          name = <<"RoomService">>,
          methods = [
            #'lg.core.grpc.VirtualService.Method'{name = <<"GetStats">>}
          ],
          cmp = 'PREEMPTIVE'
        }},
        endpoint = #'lg.core.network.Endpoint'{host = Host, port = Port}
      }
    }}
  },
  Data = registry_definitions:encode_msg(Pdu),
  ok = echo_grpc_client:grpc_data(whereis(echo_grpc_client), StreamRef, Data),
  {keep_state, S0#state{stream_ref = StreamRef}};

handle_event(info, ?grpc_event_response(StreamRef, _IsFin, _Status, _Headers), ?fsm_state_on_init_control_stream(), #state{
  stream_ref = StreamRef
} = _S0) ->
  keep_state_and_data;

handle_event(info, ?grpc_event_data(StreamRef, _IsFin, Data), ?fsm_state_on_init_control_stream(), #state{
  stream_ref = StreamRef
} = S0) ->
  #'lg.service.router.ControlStreamEvent'{
    id = #'lg.core.trait.Id'{tag = <<"init_rq">>},
    event = {init_rs, #'lg.service.router.ControlStreamEvent.InitRs'{
      session_id = SessionId,
      result = #'lg.core.trait.Result'{status = 'SUCCESS'}
    }}
  } = registry_definitions:decode_msg(Data, 'lg.service.router.ControlStreamEvent'),
  ?l_debug(#{text => "ControlStream established", result => ok, details => #{session_id => SessionId, stream_ref => S0#state.stream_ref}}),
  {next_state, ?fsm_state_on_operational(), S0#state{session_id = SessionId}};

handle_event({call, From}, ?msg_register_agent(AgentId, AgentInstance), ?fsm_state_on_operational(), #state{
  stream_ref = StreamRef
} = S0) ->
  Pdu = #'lg.service.router.ControlStreamEvent'{
    id = #'lg.core.trait.Id'{tag = <<"register-agent-", AgentId/binary>>},
    event = {register_agent_rq, #'lg.service.router.ControlStreamEvent.RegisterAgentRq'{
      agent_id = AgentId,
      agent_instance = AgentInstance
    }}
  },
  Data = registry_definitions:encode_msg(Pdu),
  ok = echo_grpc_client:grpc_data(whereis(echo_grpc_client), StreamRef, Data),
  {keep_state, S0#state{agent_id = AgentId, from = From}}; % dirty demo, zero concurrency here

handle_event(info, ?grpc_event_data(StreamRef, _IsFin, Data), ?fsm_state_on_operational(), #state{
  stream_ref = StreamRef, agent_id = AgentId, from = From
} = S0) ->
  #'lg.service.router.ControlStreamEvent'{
    id = #'lg.core.trait.Id'{tag = <<"register-agent-", AgentId/binary>>},
    event = {register_agent_rs, #'lg.service.router.ControlStreamEvent.RegisterAgentRs'{
      agent_id = AgentId,
      agent_instance = AgentInstance,
      result = #'lg.core.trait.Result'{status = 'SUCCESS'}
    }}
  } = registry_definitions:decode_msg(Data, 'lg.service.router.ControlStreamEvent'),
  ?l_debug(#{text => "Agent registered", result => ok, details => #{
    agent_id => AgentId, agent_instance => AgentInstance, stream_ref => S0#state.stream_ref
  }}),
  {next_state, ?fsm_state_on_operational(), S0#state{agent_id = undefined, from = undefined}, [{reply, From, ok}]};

%% Default handler, warn and drop
handle_event(EventType, EventContent, State, _S0) ->
  ?l_warning(#{
    text => "Unexpected event",
    what => event,
    details => #{fsm_state => State, event_type => EventType, event_content => EventContent}
  }),
  keep_state_and_data.



%% Internals
