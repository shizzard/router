-module(router_grpc_h_test).

-include_lib("router_log/include/router_log.hrl").
-include_lib("router_pb/include/test_definitions.hrl").

-export([init/0, empty_call/2]).

-record(state, {}).




%% Interface



-spec init() -> #state{}.

init() -> {ok, #state{}}.



-spec empty_call(term(), term()) ->
  {ok, term(), term()}.

empty_call(PDU, S0) ->
  ?l_info(#{text => "Handler call", what => empty_call, details => #{pdu => PDU}}),
  {ok, {#'grpc.testing.Empty'{}, S0}}.
