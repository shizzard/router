-module('router_log').
-include_lib("kernel/include/logger.hrl").

-export([component/0, component/1]).
-export([log_map/1, log_meta/1]).

-define(default_log, #{
  what => 'trace',                    %% event | command | trace
  text => 'NONE',                     %% human readable text
  result => 'NONE',                   %% ok | error | <...>
  details => 'NONE'                   %% arbitrary map of additional log parameters
}).

-define(default_meta, #{
  id => uuid:uuid_to_string(uuid:get_v4_urandom()),
  in => ?MODULE:component()     %% system high-level component
}).

-define(component_key, '$ROUTER_COMPONENT$').



%% Interface



-spec component() -> atom().

component() ->
  case erlang:get(?component_key) of
    undefined -> 'NONE';
    Component -> Component
  end.



-spec component(Component :: atom()) -> ok.

component(Component) ->
  erlang:put(?component_key, Component),
  ok.



-spec log_map(InMap :: map()) ->
  Ret :: map().

log_map(InMap) ->
  maps:merge(?default_log, InMap).



-spec log_meta(InMap :: map()) ->
  Ret :: map().

log_meta(InMap) ->
  maps:merge(?default_meta, InMap).
