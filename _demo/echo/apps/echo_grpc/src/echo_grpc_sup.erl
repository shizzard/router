-module('echo_grpc_sup').
-behaviour(supervisor).

-include_lib("echo_log/include/echo_log.hrl").
-include_lib("typr/include/typr_specs_supervisor.hrl").

-export([start_link/0, init/1]).
%% used within integration tests
-export([start_cowboy/1, stop_cowboy/0]).



%% Interface



-spec start_link() ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: {already_started, pid()} | {shutdown, term()} | term()
  ).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).



init([]) ->
  echo_log:component(echo_grpc),

  ok = init_prometheus_metrics(),
  {ok, Port} = echo_config:get(echo_grpc, [listener, port]),
  {ok, RouterHost} = echo_config:get(echo_grpc, [client, host]),
  {ok, RouterPort} = echo_config:get(echo_grpc, [client, port]),
  ok = start_cowboy(Port),
  ?l_info(#{text => "gRPC listener started", what => init, result => ok, details => #{port => Port}}),

  SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
  Children = [
    #{
      id => echo_grpc_client,
      start => {echo_grpc_client, start_link, [RouterHost, RouterPort]},
      restart => permanent,
      shutdown => 5000,
      type => worker
    },
    #{
      id => echo_grpc_client_control_stream,
      start => {echo_grpc_client_control_stream, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker
    }
  ],
  {ok, {SupFlags, Children}}.



%% Internals



-spec start_cowboy(Port :: pos_integer()) ->
  typr:ok_return().

start_cowboy(Port) ->
  case cowboy:start_clear(echo_grpc_listener,
    [{port, Port}],
    #{
      env => #{dispatch => cowboy_router:compile([])},
      stream_handlers => [echo_grpc_h],
      protocols => [http2],
      idle_timeout => infinity,
      inactivity_timeout => infinity
    }
  ) of
    {ok, _} -> ok;
    {error, {already_started, _}} -> ok;
    {error, _Reason} = Ret -> Ret
  end.



-spec stop_cowboy() ->
  typr:generic_return(ErrorRet :: not_found).

stop_cowboy() ->
  cowboy:stop_listener(echo_grpc_listener).



init_prometheus_metrics() ->
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
