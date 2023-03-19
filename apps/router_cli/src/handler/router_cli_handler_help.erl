-module('router_cli_handler_help').
-behavior('router_cli_handler').
-include("router_cli.hrl").
-include("router_cli_getopt.hrl").
-include("router_cli_handler.hrl").



%% Interface



config() ->
  [
    #getopt{s = {target, undefined, undefined, string, "Print help for action"}}
  ].

additional_help_string() -> "".

dispatch(#{target := Action}, _Rest) ->
  case lists:keyfind(Action, 1, router_cli_getopt:actions()) of
    {Action, Module, _HelpString} ->
      getopt:usage(
        router_cli_getopt:extract_getopt_config(
          [#getopt{s = {verbose, $v, "verbose", {boolean, false}, "Verbose"}} | Module:config()]
        ),
        escript:script_name() ++ " " ++ Action
      ),
      router_cli_log:log(Module:additional_help_string(), []);
    false ->
      router_cli:exit(?EXIT_CODE_INVALID_ACTION, "Invalid action: '~s'", [Action])
  end;

dispatch(#{}, _Rest) ->
  router_cli_getopt:default_help().



%% Internals
