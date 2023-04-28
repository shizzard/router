-module('router_cli').
-include("router_cli.hrl").

-export([main/1, node_connect/0, exit/1, exit/2, exit/3, router_nodename/0]).



-spec main(Args :: [term()]) -> ok.

main(Args) ->
  try
    router_cli_getopt:dispatch(Args),
    ?MODULE:exit(?EXIT_CODE_OK)
  catch T:E:S ->
    ?MODULE:exit(?EXIT_CODE_UNKNOWN, "Unexpected error: ~p:~p~n~p", [T, E, S])
  end.



-spec node_connect() ->
  typr:ok_return() | no_return().

node_connect() ->
  Nodename = local_nodename(),
  net_kernel:start([Nodename, shortnames]),
  erlang:set_cookie(Nodename, router), %% magic here
  case net_adm:ping(router_nodename()) of
    pong ->
      ok;
    pang ->
      ?MODULE:exit(?EXIT_CODE_NODE_INACCESSIBLE, "Node ~p is not accessible (dead?)", [router_nodename()])
  end.



-spec exit(Code :: non_neg_integer()) ->
  no_return().

exit(Code) ->
  %% When the node is shutting down, some IO is left unprocessed.
  %% Find the proper solution later.
  timer:sleep(500),
  ok = erlang:halt(Code).



-spec exit(Code :: pos_integer(), Reason :: list()) ->
  no_return().

exit(Code, Reason) ->
  ?MODULE:exit(Code, Reason, []).



-spec exit(Code :: non_neg_integer(), Reason :: list(), Args :: list()) ->
  no_return().

exit(0, Reason, Args) ->
  router_cli_log:log(Reason, Args),
  ?MODULE:exit(0);

exit(Code, Reason, Args) ->
  router_cli_log:error(Reason, Args),
  ?MODULE:exit(Code).



-spec router_nodename() -> atom().

router_nodename() ->
  nodename("router").



%% Internals



local_nodename() ->
  %% router-DDDDD, e.g. router-27635
  nodename(
    filename:basename(escript:script_name()) ++ "-"
    ++ erlang:integer_to_list(rand:uniform(99999))
  ).

nodename(Prefix) ->
  Host = net_adm:localhost(),
  list_to_atom(Prefix ++ "@" ++ Host).
