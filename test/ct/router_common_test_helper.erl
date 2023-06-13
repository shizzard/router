-module(router_common_test_helper).

-export([init_applications_state/0, rollback_applications_state/1]).

-record(applications_state, {
  applications_list = [] :: [atom()]
}).
-opaque applications_state() :: #applications_state{}.
-export_type([applications_state/0]).



%% Interface



%% The init_applications_state/0 and rollback_applications_state/1 functions
%% are designed to work in pair. The goal here is to "remember" started applications
%% list and rollback the system state back after all tests passed. This will
%% ensure that any side-effective state is removed before starting the next suite.
%%
%% One should call the init_applications_state/0 function in init_per_suite/1
%% callback of the Common Test suite and put the resulting data into suite Config.
%% After that, in end_per_suite/1 callback, this data should be passed to the
%% rollback_applications_state/1 function, to take care of all started applications.
%%
%% See any Common Test suite for example.

-spec init_applications_state() -> Ret :: applications_state().

init_applications_state() ->
  #applications_state{
    applications_list = [App || {App, _Info, _Version} <- application:which_applications()]
  }.



-spec rollback_applications_state(State :: applications_state()) ->
  ok.

rollback_applications_state(State) ->
  [begin
    case lists:member(App, State#applications_state.applications_list) of
      true -> ok;
      false -> application:stop(App)
    end
  end || {App, _Info, _Version} <- application:which_applications()],
  ok.
