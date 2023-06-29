-module(echo_room_sup).
-behaviour(supervisor).

-include_lib("echo_log/include/echo_log.hrl").
-include_lib("typr/include/typr_specs_supervisor.hrl").

-export([start_room/2, stop_room/2]).
-export([start_link/0, init/1]).



%% Interface



-spec start_room(Name :: binary(), Secret :: binary()) ->
  typr:ok_return(OkRet :: pid()).

start_room(Name, Secret) ->
  supervisor:start_child(?MODULE, [Name, Secret]).



-spec stop_room(
  Name :: binary(),
  Pid :: erlang:pid()
) ->
  typr:generic_return(ErrorRet :: not_found).

stop_room(Name, Pid) ->
  supervisor:terminate_child(echo_room:pid(Name), Pid).



-spec start_link() ->
  typr:generic_return(
    OkRet :: pid(),
    ErrorRet :: {already_started, pid()} | {shutdown, term()} | term()
  ).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, {}).



init({}) ->
  echo_log:component(echo_room),
  ok = init_prometheus_metrics(),
  SupFlags = #{strategy => simple_one_for_one, intensity => 10, period => 10},
  Children = [
    #{
      id => ignored,
      start => {echo_room, start_link, []},
      restart => transient,
      shutdown => 5000,
      type => supervisor
    }
  ],
  {ok, {SupFlags, Children}}.



%% Internals



init_prometheus_metrics() ->
  ok.
