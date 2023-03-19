-export([config/0, dispatch/2, additional_help_string/0]).

-spec config() ->
  router_cli_getopt:getopt_config().

-spec dispatch(ParsedArgs :: list(), Rest :: list()) ->
  ok.

-spec additional_help_string() ->
  string().
