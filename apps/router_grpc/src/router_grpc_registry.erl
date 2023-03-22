-module(router_grpc_registry).
-behaviour(gen_server).

-compile([nowarn_untyped_record]).

-include("router_grpc_registry.hrl").
-include_lib("gpb/include/gpb.hrl").
-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").

-export([lookup/1]).
-export([
  start_link/2, init/1,
  handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3
]).

-record(state, {
  ets :: ets:tid()
}).
-type state() :: #state{}.

-type definition() :: #router_grpc_registry_definition{}.
-export_type([definition/0]).

-define(service_method_id(Service, Method), {Service, Method}).



%% Messages

% -define(call_set_proxy(Provider, Id, Proxy), {call_set_proxy, Provider, Id, Proxy}).
% -define(call_remove_proxy(Provider, Id), {call_remove_proxy, Provider, Id}).


%% Metrics

% -define(metric_gge_proxies_amount, router_proxy_registry_proxies_amount).



%% Interface



-spec lookup(Path :: binary()) ->
  typr:generic_return(
    OkRet :: definition(),
    ErrorRet :: undefined
  ).

lookup(Path) ->
  try
    [ServiceName, MethodName] = [
      binary_to_existing_atom(Part) || Part
      <- binary:split(Path, <<"/">>, [global]), Part =/= <<>>
    ],
    case ets:lookup(?MODULE, ?service_method_id(ServiceName, MethodName)) of
      [Definition] -> {ok, Definition};
      [] -> {error, undefined}
    end
  catch
    _:_ -> {error, undefined}
  end.



-spec start_link(ServiceDefinitions :: [atom(), ...], ServiceMap :: #{atom() => atom()}) ->
  typr:ok_return(OkRet :: pid()).

start_link(ServiceDefinitions, ServiceMap) ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, {ServiceDefinitions, ServiceMap}, []).



init({ServiceDefinitions, ServiceMap}) ->
  router_log:component(router_grpc),
  ok = quickrand:seed(),
  ok = init_prometheus_metrics(),

  S0 = #state{
    ets = ets:new(?MODULE,
      [ordered_set, protected, named_table, {read_concurrency, true},
      {keypos, #router_grpc_registry_definition.id}]
    )
  },
  init_ets_table(ServiceDefinitions, ServiceMap, S0),
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



init_ets_table([], _ServiceMap, S0) -> {ok, S0};

init_ets_table([ServiceDefinition | ServiceDefinitions], ServiceMap, S0) ->
  ServiceNames = ServiceDefinition:get_service_names(),
  [init_ets_table_service(ServiceName, ServiceDefinition, ServiceMap, S0) || ServiceName <- ServiceNames],
  init_ets_table(ServiceDefinitions, ServiceMap, S0).



init_ets_table_service(ServiceName, ServiceDefinition, ServiceMap, S0) ->
  case maps:get(ServiceName, ServiceMap, undefined) of
    undefined -> ok;
    ModuleName ->
      {{service, ServiceName}, Methods} = ServiceDefinition:get_service_def(ServiceName),
      MethodDefinitions = [
        #router_grpc_registry_definition{
          id = ?service_method_id(ServiceName, MethodName), definition = ServiceDefinition,
          service = ServiceName, method = MethodName, module = ModuleName, function = atom_snake_case(MethodName),
          input = Input, output = Output, input_stream = InputStream, output_stream = OutputStream, opts = Opts
        } || #rpc{
          name = MethodName, input = Input, output = Output,
          input_stream = InputStream, output_stream = OutputStream, opts = Opts
        } <- Methods
      ],
      ets:insert(S0#state.ets, MethodDefinitions)
  end.


atom_snake_case(Name) ->
  NameString = atom_to_list(Name),
  Snaked = lists:foldl(
    fun(RE, Snaking) ->
      re:replace(Snaking, RE, "\\1_\\2", [{return, list}, global])
    end, NameString,
    [
      "(.)([A-Z][a-z]+)", %% uppercase followed by lowercase
      "(.)([0-9]+)", %% any consecutive digits
      "([a-z0-9])([A-Z])" %% uppercase with lowercase or digit before it
    ]
  ),
  Snaked1 = string:replace(Snaked, ".", "_", all),
  Snaked2 = string:replace(Snaked1, "__", "_", all),
  list_to_atom(string:to_lower(unicode:characters_to_list(Snaked2))).
