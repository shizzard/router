-module('router_config').

-export([get/2, set/3]).



%% Interface



-spec get(App :: atom(), Keys :: [atom()] | atom()) ->
  typr:generic_return(
    OkRet :: term(),
    ErrorRet :: undefined
  ).

get(App, Keys) ->
  get_impl(application:get_all_env(App), Keys).



-spec set(App :: atom(), Keys :: [atom()] | atom(), Value :: term()) ->
  typr:generic_return(ErrorRet :: undefined).

set(App, Keys, Value) ->
  case set_impl(application:get_all_env(App), Keys, Value) of
    {ok, NewEnv} ->
      application:set_env([{App, NewEnv}], [{persistent, true}]);
    {error, undefined} ->
      {error, undefined}
  end.



%% Internals



get_impl(Value, Key) when not is_list(Key) ->
  get_impl(Value, [Key]);

get_impl(undefined, _Keys) ->
  {error, undefined};

get_impl(Value, []) ->
  {ok, Value};

get_impl(Proplist0, [Key | Keys]) when is_list(Proplist0) ->
  Proplist1 = proplists:get_value(Key, Proplist0),
  get_impl(Proplist1, Keys);

get_impl(_Value, Keys) ->
  get_impl(undefined, Keys).



set_impl(Value, Key, NewValue) when not is_list(Key) ->
  set_impl(Value, [Key], NewValue);

set_impl(undefined, _Keys, _NewValue) ->
  {error, undefined};

set_impl(_Value, [], NewValue) ->
  {ok, NewValue};

set_impl(Proplist0, [Key | Keys], NewValue) when is_list(Proplist0) ->
  case {
    proplists:is_defined(Key, Proplist0),
    set_impl(proplists:get_value(Key, Proplist0), Keys, NewValue)
  } of
    {true, {ok, Proplist1}} ->
      {ok, [{Key, Proplist1} | proplists:delete(Key, Proplist0)]};
    {true, Ret} -> Ret;
    {false, _} -> {error, undefined}
  end;

set_impl(_Value, Keys, NewValue) ->
  set_impl(undefined, Keys, NewValue).
