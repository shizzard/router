-module('router_grpc_app').
-behaviour(application).

-include_lib("typr/include/typr_specs_application.hrl").

-export([start/2, stop/1]).



%% Interface



start(_StartType, _StartArgs) ->
  router_grpc_sup:start_link().



stop(_State) ->
  ok.



%% Internals
