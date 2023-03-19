-module('router_sup').
-behaviour(supervisor).

-include_lib("typr/include/typr_specs_supervisor.hrl").

-export([update_connections_limit/1]).
-export([start_link/0, init/1]).

-define(listener, router_listener).



%% Interface



-spec update_connections_limit(N :: pos_integer()) ->
  type:ok_return().

update_connections_limit(N) when N > 0 ->
  ranch:set_max_connections(?listener, N).



-spec start_link() ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: {already_started, pid()} | {shutdown, term()} | term()
  ).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).



init([]) ->
  router_log:component(router),

  ok = init_tunnel_prometheus_metrics(),
  SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
  Children = [],
  {ok, {SupFlags, Children}}.



%% Internals



init_tunnel_prometheus_metrics() ->
  % prometheus_summary:declare([
  %   {name, ?metric_smr_foo},
  %   {labels, [a, b]},
  %   {help, "Help"}
  % ]),
  % prometheus_histogram:new([
  %   {name, ?metric_hgr_foo},
  %   {labels, [a, b]},
  %   {buckets, [1 * trunc(math:pow(2, E)) || E <- lists:seq(0, 7)]},
  %   {help, "Help"}
  % ]),
  % prometheus_counter:new([
  %   {name, ?metric_cnt_foo},
  %   {labels, [a, b]},
  %   {help, "Help"}
  % ]).
  ok.
