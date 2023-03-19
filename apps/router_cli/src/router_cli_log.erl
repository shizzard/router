-module(router_cli_log).
-compile({no_auto_import, [error/2]}).

-export([error/1, error/2, warning/1, warning/2, log/1, log/2]).



%% Interface



-spec error(Fmt :: list()) -> ok.
error(Fmt) -> error(Fmt, []).
-spec error(Fmt :: list(), Args :: list()) -> ok.
error(Fmt, Args) -> format("[error] ", Fmt, Args).

-spec warning(Fmt :: list()) -> ok.
warning(Fmt) -> warning(Fmt, []).
-spec warning(Fmt :: list(), Args :: list()) -> ok.
warning(Fmt, Args) -> format("[warning] ", Fmt, Args).

-spec log(Fmt :: list()) -> ok.
log(Fmt) -> log(Fmt, []).
-spec log(Fmt :: list(), Args :: list()) -> ok.
log(Fmt, Args) -> format("", Fmt, Args).



%% Internals



format(Prefix, Fmt, Args) ->
  io:format(Prefix ++ Fmt ++ "~n", Args).
