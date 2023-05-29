-module(router_grpc_client_pool_SUITE_client).
-behaviour(gen_statem).

-include_lib("router_grpc/include/router_grpc_service_registry.hrl").

-export([start_link/1, start_link/2, init/1, callback_mode/0, handle_event/4]).

-record(state, {}).
-type state() :: #state{}.

%% FSM States

-define(fsm_state_on_init(), {fsm_state_on_init}).

-type fsm_state() :: ?fsm_state_on_init().

%% State transition messages

-define(msg_gun_connect(), {msg_gun_connect}).

%% Incoming calls messages



%% Interface



-spec start_link(
  Definition :: router_grpc:definition_external()
) ->
  typr:ok_return(OkRet :: pid()).

start_link(Definition) ->
  gen_statem:start_link(?MODULE, [Definition], []).



-spec start_link(
  Host :: string(),
  Port :: pos_integer()
) ->
  typr:ok_return(OkRet :: pid()).

start_link(Host, Port) ->
  gen_statem:start_link(?MODULE, [Host, Port], []).



-spec init([term()]) ->
  {ok, FsmState :: fsm_state(), S0 :: state()}.

init([_Definition]) ->
  {ok, ?fsm_state_on_init(), #state{}};

init([_Host, _Port]) ->
  {ok, ?fsm_state_on_init(), #state{}}.



-spec callback_mode() -> handle_event_function.

callback_mode() ->
  handle_event_function.



%% States



-spec handle_event(atom(), term(), atom(), state()) ->
  gen_statem:event_handler_result(FsmState :: fsm_state()).

handle_event(_EventType, _EventContent, _State, _S0) ->
  keep_state_and_data.



%% Internals
