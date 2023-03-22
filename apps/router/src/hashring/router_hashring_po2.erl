-module(router_hashring_po2).

-export([new/2, new/3, map/2, child_specs/2, child_specs/3]).

-record(?MODULE, {
  hash_algorithm :: atom(),
  hr_bitsize :: hr_bitsize(),
  hr_buckets_po2 :: hr_buckets_po2(),
  hr_nodes_po2 :: hr_nodes_po2()
}).

-type hash_algorithm() :: crypto:hash_algorithm().
-type hr_bitsize() :: pos_integer().
-type hr_buckets_po2() :: pos_integer().
-type hr_nodes_po2() :: pos_integer().
-type hr_bucket() :: non_neg_integer().
-type hr_node() :: non_neg_integer().
-type hr_node_buckets_spec() :: #{node => hr_node(), buckets => [hr_bucket(), ...]}.
-opaque t() :: #?MODULE{}.
-export_type([
  hash_algorithm/0, hr_bitsize/0,
  hr_buckets_po2/0, hr_nodes_po2/0, hr_bucket/0, hr_node/0, hr_node_buckets_spec/0,
  t/0
]).

-define(default_hash_algorithm, sha3_256).



%% Interface



-spec new(BucketsPO2 :: hr_buckets_po2(), NodesPO2 :: hr_nodes_po2()) ->
  typr:generic_return(
    OkRet :: t(),
    ErrorRet ::
      {invalid_hash_algorithm, HashAlgorithm :: hash_algorithm()}
    | {invalid_parameters, hr_buckets_po2_lt_hr_nodes_po2}
  ).

new(BucketsPO2, NodesPO2) -> new(BucketsPO2, NodesPO2, ?default_hash_algorithm).



-spec new(BucketsPO2 :: hr_buckets_po2(), NodesPO2 :: hr_nodes_po2(), HashAlgorithm :: hash_algorithm()) ->
  typr:generic_return(
    OkRet :: t(),
    ErrorRet ::
      {invalid_hash_algorithm, HashAlgorithm :: hash_algorithm()}
    | {invalid_parameters, hr_buckets_po2_lt_hr_nodes_po2}
  ).

new(BucketsPO2, NodesPO2, HashAlgorithm)
when is_integer(BucketsPO2), is_integer(NodesPO2), BucketsPO2 >= NodesPO2 ->
  try
    #{size := Octets} = crypto:hash_info(HashAlgorithm),
    {ok, #?MODULE{
      hash_algorithm = HashAlgorithm,
      hr_bitsize = Octets * 8,
      hr_buckets_po2 = BucketsPO2,
      hr_nodes_po2 = NodesPO2
    }}
  catch error:badarg ->
    {error, {invalid_hash_algorithm, HashAlgorithm}}
  end;

new(_BucketsPO2, _NodesPO2, _HashAlgorithm) ->
  {error, {invalid_parameters, hr_buckets_po2_lt_hr_nodes_po2}}.



-spec child_specs(Hashring :: t(), ChildSpec :: supervisor:child_spec()) ->
  Ret :: [supervisor:child_spec(), ...].

child_specs(HR, ChildSpec) ->
  child_specs(HR, ChildSpec, #{}).



-spec child_specs(Hashring :: t(), ChildSpec :: supervisor:child_spec(), Opts :: map()) ->
  Ret :: [supervisor:child_spec(), ...].

child_specs(#?MODULE{hr_buckets_po2 = BucketsPO2, hr_nodes_po2 = NodesPO2}, ChildSpec, Opts) ->
  BucketsPerNode = erlang:floor(math:pow(2, BucketsPO2 - NodesPO2)),
  TotalNodes = erlang:floor(math:pow(2, NodesPO2)),
  lists:reverse(lists:foldl(fun(Node, Acc) ->
    [
      child_spec(
        Node,
        lists:reverse([Node * BucketsPerNode - BucketN || BucketN <- lists:seq(0, BucketsPerNode - 1)]),
        ChildSpec,
        Opts
      ) | Acc
    ]
  end, [], lists:seq(1, TotalNodes))).



-spec map(Hashring :: t(), Term :: term()) ->
  Ret :: {Node :: hr_node(), Bucket :: hr_bucket()}.

map(#?MODULE{
  hash_algorithm = HashAlgorithm,
  hr_buckets_po2 = BucketsPO2,
  hr_nodes_po2 = NodesPO2
}, Term) ->
  Hash = crypto:hash(HashAlgorithm, erlang:term_to_binary(Term)),
  <<Bucket:BucketsPO2, _/bitstring>> = Hash,
  <<Node:NodesPO2, _/bitstring>> = Hash,
  {Node, Bucket}.



%% Internals



child_spec(Node, Buckets, #{start := {M, F, A}} = ChildSpec0, Opts) ->
  AccIn = {Node, Buckets, ChildSpec0#{start := {M, F, A ++ [#{node => Node, buckets => Buckets}]}}},
  {_Node, _Buckets, ChildSpec1} = maps:fold(fun child_spec_map/3, AccIn, Opts),
  ChildSpec1.



child_spec_map(id_fun, Fun, {Node, Buckets, ChildSpec}) ->
  {M, F, A} = maps:get(start, ChildSpec),
  Id = Fun(Node),
  {Node, Buckets, ChildSpec#{id := Id, start := {M, F, A ++ [Id]}}};

child_spec_map(_OptKey, _OptValue, AccIn) -> AccIn.
