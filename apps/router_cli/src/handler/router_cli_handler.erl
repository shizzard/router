-module(router_cli_handler).

-callback config() ->
  router_cli_getopt:getopt_config().
-callback dispatch(ParsedArgs :: list(), Rest :: list()) ->
  ok.
-callback additional_help_string() ->
  string().
