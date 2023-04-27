-module(router_grpc_pagination_tests).
-compile([export_all, nowarn_export_all, nowarn_unused_function, nowarn_missing_spec]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("typr/include/typr_specs_eunit.hrl").

-record(test_record, {
  id :: integer(),
  field_one :: binary(),
  field_two :: term()
}).

-record(test_ctx, {
  ets :: ets:tid(),
  records = [] :: [#test_record{}]
}).



%% Generators



-spec ?eunit_test(router_grpc_pagination_empty_table_test_).
router_grpc_pagination_empty_table_test_() ->
  {
    "Empty ETS table can be paginated",
    {setup, fun setup_empty_table/0, fun stop/1, fun router_grpc_pagination_empty_table_test_empty/1}
  }.



-spec ?eunit_test(router_grpc_pagination_full_table_test_).
router_grpc_pagination_full_table_test_() ->
  [{
    "ETS table can be get in full",
    {setup, fun setup_full_table/0, fun stop/1, fun router_grpc_pagination_full_table_test_get_full_list/1}
  }, {
    "ETS table can be paginated",
    {setup, fun setup_full_table/0, fun stop/1, fun router_grpc_pagination_full_table_test_get_paginated/1}
  }].



%% Tests



router_grpc_pagination_empty_table_test_empty(Ctx) ->
  Ret = router_grpc_pagination:get_list(
    Ctx#test_ctx.ets, fun match_spec/1, fun key_take/1, undefined, 20
  ),
  [?_assertEqual({ok, empty}, Ret)].



router_grpc_pagination_full_table_test_get_full_list(Ctx) ->
  {ok, {final_page, List}} = router_grpc_pagination:get_list(
    Ctx#test_ctx.ets, fun match_spec/1, fun key_take/1, undefined, 20
  ),
  [
    ?_assertEqual(20, length(List)),
    ?_assertEqual(Ctx#test_ctx.records, List)
  ].



router_grpc_pagination_full_table_test_get_paginated(#test_ctx{ets = Ets, records = Records0}) ->
  {ok, {page, List1, PageToken1}} = router_grpc_pagination:get_list(
    Ets, fun match_spec/1, fun key_take/1, undefined, 7
  ),
  {Records1to7, Records8to20} = lists:split(7, Records0),
  Tests1 = [
    ?_assertEqual(7, length(List1)),
    ?_assertEqual(Records1to7, List1)
  ],
  {ok, {page, List2, PageToken2}} = router_grpc_pagination:get_list(
    Ets, fun match_spec/1, fun key_take/1, PageToken1, 7
  ),
  {Records8to14, Records15to20} = lists:split(7, Records8to20),
  Tests2 = [
    ?_assertEqual(7, length(List2)),
    ?_assertEqual(Records8to14, List2)
  ],
  {ok, {final_page, List3}} = router_grpc_pagination:get_list(
    Ets, fun match_spec/1, fun key_take/1, PageToken2, 7
  ),
  Tests3 = [
    ?_assertEqual(6, length(List3)),
    ?_assertEqual(Records15to20, List3)
  ],
  Tests1 ++ Tests2 ++ Tests3.



%% Setup and teardown



setup_empty_table() ->
  Ets = ets:new(?MODULE,
    [ordered_set, protected, named_table, {read_concurrency, true},
    {keypos, #test_record.id}]
  ),
  #test_ctx{ets = Ets}.



setup_full_table() ->
  Ets = ets:new(?MODULE,
    [ordered_set, protected, named_table, {read_concurrency, true},
    {keypos, #test_record.id}]
  ),
  Records = [
    #test_record{id = Id, field_one = <<"FieldOne-", (integer_to_binary(Id))/binary>>, field_two = {field_two, Id}}
    || Id <- lists:seq(1, 20)
  ],
  ets:insert(Ets, Records),
  #test_ctx{ets = Ets, records = Records}.



stop(Ctx) ->
  ets:delete(Ctx#test_ctx.ets).



%% Helpers



match_spec(Key) ->
  [{{'_','$1','_','_'}, [{'>=','$1', {const,Key}}], ['$_']}].

key_take(#test_record{id = Id}) -> Id.
