-module(router_hashring_po2_tests).
-compile([export_all, nowarn_export_all, nowarn_unused_function]).
-dialyzer({nowarn_function, [
  can_generate_child_specs_test/0,
  can_generate_child_specs_with_idfun_test/0
]}).

-include_lib("eunit/include/eunit.hrl").
-include_lib("typr/include/typr_specs_eunit.hrl").

-spec ?eunit_test(test).

-spec ?eunit_test(can_create_new_hashring_test).
can_create_new_hashring_test() ->
  %% buckets_po2 gt nodes_po2
  {ok, _} = router_hashring_po2:new(10, 8),
  %% buckets_po2 eq nodes_po2
  {ok, _} = router_hashring_po2:new(8, 8),
  %% buckets_po2 lt nodes_po2
  {error, {invalid_parameters, hr_buckets_po2_lt_hr_nodes_po2}} =
    router_hashring_po2:new(7, 8),
  %% valid hash functions
  {ok, _} = router_hashring_po2:new(10, 8, sha3_512),
  {ok, _} = router_hashring_po2:new(10, 8, blake2s),
  %% invalid hash function
  {error, {invalid_hash_algorithm, undefined_hash_algorithm}} =
    router_hashring_po2:new(10, 8, undefined_hash_algorithm),
  ok.

-spec ?eunit_test(can_generate_child_specs_test).
can_generate_child_specs_test() ->
  BucketsPO2 = 4,
  NodesPO2 = 2,
  {ok, HR} = router_hashring_po2:new(BucketsPO2, NodesPO2),
  ChildSpec = #{start => {module, function, [a,r,g,s]}},
  ChildSpecs = router_hashring_po2:child_specs(HR, ChildSpec),
  %% Number of child specs equals to number of nodes
  ?assertEqual(floor(math:pow(2, NodesPO2)), length(ChildSpecs)),
  %% Hashring appends node-buckets spec to the end of the args list
  lists:foreach(fun
    (#{start := {module, function, [a,r,g,s, #{node := _, buckets := Buckets}]}}) ->
      ?assertEqual(floor(math:pow(2, BucketsPO2 - NodesPO2)), length(Buckets))
  end, ChildSpecs),
  ok.

-spec ?eunit_test(can_generate_child_specs_with_idfun_test).
can_generate_child_specs_with_idfun_test() ->
  BucketsPO2 = 4,
  NodesPO2 = 2,
  {ok, HR} = router_hashring_po2:new(BucketsPO2, NodesPO2),
  ChildSpec = #{id => fake_id, start => {module, function, [a,r,g,s]}},
  ChildSpecs = router_hashring_po2:child_specs(HR, ChildSpec, #{id_fun => fun(Node) -> {fake_id, Node} end}),
  %% Number of child specs equals to number of nodes
  ?assertEqual(floor(math:pow(2, NodesPO2)), length(ChildSpecs)),
  %% Hashring appends node-buckets spec to the end of the args list
  lists:foreach(fun
    (#{
      id := {fake_id, Node},
      start := {module, function, [a,r,g,s, #{node := Node, buckets := Buckets}, {fake_id, Node}]}
    }) ->
      ?assertEqual(floor(math:pow(2, BucketsPO2 - NodesPO2)), length(Buckets))
  end, ChildSpecs),
  ok.
