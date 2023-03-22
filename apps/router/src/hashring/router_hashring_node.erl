-module(router_hashring_node).
-behaviour(gen_server).

-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").

-export([]).
-export([
  start_link/2, init/1,
  handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3
]).

-record(state, {
  id :: atom(),
  node :: router_hashring_po2:hr_node(),
  buckets :: [router_hashring_po2:hr_bucket(), ...]
}).
-type state() :: #state{}.


-export_type([]).



%% Messages

% -define(call_set_proxy(Provider, Id, Proxy), {call_set_proxy, Provider, Id, Proxy}).
% -define(call_remove_proxy(Provider, Id), {call_remove_proxy, Provider, Id}).


%% Metrics

% -define(metric_gge_proxies_amount, router_proxy_registry_proxies_amount).



%% Interface



-spec start_link(HRSpec :: map(), Id :: atom()) ->
  typr:ok_return(OkRet :: pid()).

start_link(HRSpec, Id) ->
  gen_server:start_link({local, Id}, ?MODULE, {HRSpec, Id}, []).



init({#{buckets := Buckets, node := Node}, Id}) ->
  router_log:component(router_hashring),
  ok = quickrand:seed(),
  ok = init_prometheus_metrics(),
  S0 = #state{id = Id, node = Node, buckets = Buckets},
  {ok, S0}.



%% Handlers



handle_call(Unexpected, _GenReplyTo, S0) ->
  ?l_error(#{text => "Unexpected call", what => handle_call, details => Unexpected}),
  {reply, badarg, S0}.



handle_cast(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected cast", what => handle_cast, details => Unexpected}),
  {noreply, S0}.



handle_info(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected info", what => handle_info, details => Unexpected}),
  {noreply, S0}.



terminate(_Reason, _S0) ->
  ok.



code_change(_OldVsn, S0, _Extra) ->
  {ok, S0}.



%% Internals



init_prometheus_metrics() ->
  ok.
