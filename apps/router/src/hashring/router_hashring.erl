-module(router_hashring).

-export([init/2, get/0, node_name/1]).

-define(global_hashring, {router_hashring, global_hashring}).



%% Interface



-spec init(
  BucketPO2 :: router_hashring_po2:hr_buckets_po2(),
  NodesPO2 :: router_hashring_po2:hr_nodes_po2()
) ->
  typr:ok_return().

init(BucketsPO2, NodesPO2) ->
  {ok, HR} = router_hashring_po2:new(BucketsPO2, NodesPO2),
  persistent_term:put(?global_hashring, HR).



-spec get() ->
  typr:generic_return(
    OkRet :: router_hashring_po2:t(),
    ErrorRet :: undefined
  ).

get() ->
  case persistent_term:get(?global_hashring, undefined) of
    undefined -> {error, undefined};
    HR -> {ok, HR}
  end.



-spec node_name(Node :: router_hashring_po2:hr_node()) ->
  atom().

node_name(Node) ->
  list_to_atom(lists:flatten(["router_hashring_node[", integer_to_list(Node), "]"])).
