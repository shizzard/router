-module(router_grpc_pagination).

-export([get_list/5]).

-define(magic_string, 16#a11600d:4/integer-unit:8).



%% Interface



-spec get_list(
  Ets :: ets:tid() | atom(),
  EtsMatchSpecFun :: fun((ElemKey :: term()) -> ets:match_spec()),
  KeyTakeFun :: fun((Elem :: term()) -> ElemKey :: term()),
  PageToken :: binary() | undefined,
  PageSize :: pos_integer()
) ->
  typr:generic_return(
    OkRet ::
      {final_page, List :: [term()]} |
      {page, List :: [term()], NextPageToken :: binary()} |
      empty,
    ErrorRet :: invalid_token
  ).

get_list(Ets, EtsMatchSpecFun, KeyTakeFun, undefined, PageSize) ->
  case ets:first(Ets) of
    '$end_of_table' -> {ok, empty};
    Key -> get_page(Ets, EtsMatchSpecFun, KeyTakeFun, Key, PageSize)
  end;

get_list(Ets, EtsMatchSpecFun, KeyTakeFun, PageToken, PageSize) ->
  case decode_page_token(PageToken) of
    {ok, PrevPageLastKey} ->
      case ets:next(Ets, PrevPageLastKey) of
        '$end_of_table' -> {ok, empty};
        Key -> get_page(Ets, EtsMatchSpecFun, KeyTakeFun, Key, PageSize)
      end;
    {error, _Reason} ->
      {error, invalid_token}
  end.



%% Internals



get_page(Ets, EtsMatchSpecFun, KeyTakeFun, Key, PageSize) ->
  case ets:select(Ets, EtsMatchSpecFun(Key), PageSize + 1) of
    '$end_of_table' ->
      {ok, empty};
    {List, '$end_of_table'} ->
      {ok, {final_page, List}};
    {List, _Continuation} ->
      SubList = lists:sublist(List, PageSize),
      {ok, {page, SubList, encode_page_token(KeyTakeFun(lists:last(SubList)))}}
  end.



decode_page_token(String) ->
  try
    <<?magic_string, BinTerm/binary>> = base64:decode(String),
    Term = binary_to_term(BinTerm, [safe]),
    {ok, Term}
  catch
    _:_ -> {error, invalid_token}
  end.



encode_page_token(Term) ->
  BinTerm = <<?magic_string, (term_to_binary(Term))/binary>>,
  base64:encode(BinTerm).
