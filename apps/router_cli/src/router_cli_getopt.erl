-module(router_cli_getopt).
-include("router_cli.hrl").
-include("router_cli_getopt.hrl").

-export([dispatch/1, actions/0, default_help/0, merged_config/1, extract_getopt_config/1]).

-type arg_type() :: 'atom' | 'binary' | 'utf8_binary' | 'boolean' | 'float' | 'integer' | 'string'.
-type arg_value() :: atom() | binary() | boolean() | float() | integer() | string().
-type arg_spec() :: arg_type() | {arg_type(), arg_value()} | undefined.
%% Example: {host, $h, "host", {string, "localhost"}, "Database server host"}
-type getopt_config() :: [{
    Name :: atom(),
    Short :: char() | undefined,
    Long :: string() | undefined,
    ArgSpec :: arg_spec(),
    Help :: string() | undefined
  }].

-export_type([getopt_config/0]).

-define(config(), [
  #getopt{s = {action, undefined, undefined, {string, actions}, default_config_list_actions()}}
]).



%% Interface



-spec dispatch(Args :: list()) ->
  ok | no_return().
dispatch([Action | _] = Args) ->
  dispatch_action(Action, Args);
dispatch([]) ->
  dispatch_action("actions", []).

-spec actions() ->
  list({Action :: list, Module :: atom(), HelpString :: list()}).
actions() ->
  [
    {"actions", router_cli_handler_actions, "List available actions"},
    {"help", router_cli_handler_help, "Print help"},
    {"proxy", router_cli_handler_proxy, "Proxy management"}
  ].

-spec default_help() ->
  ok.
default_help() ->
  getopt:usage(extract_getopt_config(?config()), escript:script_name()).

-spec merged_config(Module :: atom()) ->
  [#getopt{}].
merged_config(Module) ->
  ?config() ++ Module:config().

-spec extract_getopt_config(Config :: [#getopt{}]) ->
  GetoptConfig :: [getopt_config()].
extract_getopt_config(Config) ->
  [S || #getopt{s = S} <- Config].



%% Internals



default_config_list_actions() ->
  lists:flatten(lists:join("|", [A || {A, _Module, _HelpString} <- actions()])).

dispatch_action(Action, Args) ->
  case lists:keyfind(Action, 1, actions()) of
    {Action, Module, _HelpString} ->
      dispatch_action_parse(Module, Args);
    false ->
      router_cli:exit(?EXIT_CODE_INVALID_ACTION, "Invalid action: '~s'", [Action])
  end.

dispatch_action_parse(Module, Args) ->
  MergedConfig = merged_config(Module),
  case getopt:parse(extract_getopt_config(MergedConfig), Args) of
    {ok, {ParsedArgs, Rest}} ->
      dispatch_action_validate(Module, MergedConfig, ParsedArgs, Rest);
    {error, {Reason, _Data}} ->
      router_cli:exit(?EXIT_CODE_GETOPT_FAILED, "Failed to parse command: ~p", [Reason])
  end.

dispatch_action_validate(Module, MergedConfig, ParsedArgs, Rest) ->
  RequiredArgs = [S || #getopt{r = true, s = S} <- MergedConfig],
  case lists:filter(
    fun({A, _, _, _, _}) -> proplists:lookup(A, ParsedArgs) == none end,
    RequiredArgs
  ) of
    [] ->
      Module:dispatch(dispatch_action_validate_parsed_args_to_map(ParsedArgs, merged_config(Module)), Rest);
    MissingArgs ->
      router_cli:exit(
        ?EXIT_CODE_MISSING_ARGS,
        "Missing mandatory arguments: ~ts~n"
        "Try '~ts help <action>' command",
        [
          lists:flatten(lists:join(",", [atom_to_list(A) || {A, _, _, _, _} <- MissingArgs])),
          escript:script_name()
        ]
      )
  end.

dispatch_action_validate_parsed_args_to_map(ParsedArgs, Config) ->
  % You, probably, can do the same with proplists:to_map/2, given the proper set
  % of operations, but I didn't find the solution in five minutes, so here is
  % the handwritten one.
  % Goal here is to map '[{a, x}, {a, y}, {b, z}]' to '#{a => [x, y], b => z}'
  {Ret, _} = lists:foldl(fun dispatch_action_validate_parsed_args_to_map_fold/2, {#{}, Config}, ParsedArgs),
  Ret.

dispatch_action_validate_parsed_args_to_map_fold({Key, Value}, {Acc, Config}) ->
  IsListOption = lists:any(fun
    (#getopt{l = L, s = {OptionKey, _, _, _, _}}) when Key == OptionKey -> L;
    (_) -> false
  end, Config),
  case Acc of
    #{Key := ExistingList} when IsListOption -> {Acc#{Key := [Value | ExistingList]}, Config};
    #{Key := _ExistingValue} -> {Acc#{Key := Value}, Config};
    Acc when IsListOption -> {Acc#{Key => [Value]}, Config};
    Acc -> {Acc#{Key => Value}, Config}
  end.
