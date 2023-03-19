-record(getopt, {
  % required?
  r = false :: boolean(),
  % list?
  l = false :: boolean(),
  % specification
  s = erlang:error(not_initialized) :: router_cli_getopt:getopt_config()
}).
