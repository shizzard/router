-module(router_cli_handler_actions).
-behavior(router_cli_handler).
-include("router_cli.hrl").
-include("router_cli_getopt.hrl").
-include("router_cli_handler.hrl").



%% Interface



config() ->
  [].

additional_help_string() -> "".

dispatch(_ParsedArgs, _Rest) ->
  router_cli_log:log(lists:flatten([
    io_lib:format("~-20s ~s~n", [Action, HelpString]) || {Action, _Module, HelpString}
    <- router_cli_getopt:actions()
  ])).



%% Internals
