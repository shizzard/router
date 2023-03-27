-module(router_grpc_registry).
-behaviour(gen_server).

-compile([nowarn_untyped_record]).

-include("router_grpc_registry.hrl").
-include_lib("gpb/include/gpb.hrl").
-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").

-export([restricted_packages/0, register/1, lookup/1]).
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
-type details_internal() :: #router_grpc_registry_definition_details_internal{}.
-type details_external() :: #router_grpc_registry_definition_details_external{}.
-type details() :: details_internal() | details_external().
-export_type([definition/0, details_internal/0, details_external/0, details/0]).

-define(service_method_id(Service, Method), {Service, Method}).

-define(restricted_packages, [<<"lg.service.router">>]).



%% Messages

-define(call_register(Details), {call_register, Details}).



%% Metrics

% -define(metric_gge_proxies_amount, router_proxy_registry_proxies_amount).



%% Interface



-spec restricted_packages() -> [binary(), ...].

restricted_packages() -> ?restricted_packages.



-spec register(Details :: router_grpc_registry:details_external()) ->
  typr:generic_return(
    ErrorRet :: term()
  ).

register(#router_grpc_registry_definition_details_external{} = Details) ->
  gen_server:call(?MODULE, ?call_register(Details)).



-spec lookup(Path :: binary()) ->
  typr:generic_return(
    OkRet :: definition(),
    ErrorRet :: undefined
  ).

lookup(Path) ->
  try
    [ServiceName, MethodName] = [Part || Part <- binary:split(Path, <<"/">>, [global]),Part =/= <<>>],
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



handle_call(?call_register(#router_grpc_registry_definition_details_external{
  service = ServiceName, method = MethodName
} = Details), _GenReplyTo, S0) ->
  Definition = #router_grpc_registry_definition{
    id = ?service_method_id(ServiceName, MethodName),
    details = Details
  },
  ets:insert(S0#state.ets, Definition),
  {reply, ok, S0};

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
      init_ets_table_service_methods(ServiceName, ServiceDefinition, Methods, ModuleName, S0)
  end.



init_ets_table_service_methods(ServiceName, ServiceDefinition, Methods, ModuleName, S0) ->
  MethodDefinitions = lists:flatten([
    begin
      %% Check if configured module exports corresponding function with arity 2
      FunctionName = atom_snake_case(MethodName),
      ModuleExports = ModuleName:module_info(exports),
      ExportedArities = proplists:get_all_values(FunctionName, ModuleExports),
      case lists:member(2, ExportedArities) of
        true ->
          ServiceNameBin = atom_to_binary(ServiceName),
          MethodNameBin = atom_to_binary(MethodName),
          #router_grpc_registry_definition{
            id = ?service_method_id(ServiceNameBin, MethodNameBin),
            details = #router_grpc_registry_definition_details_internal{
              definition = ServiceDefinition, service = ServiceNameBin, method = MethodNameBin,
              module = ModuleName, function = FunctionName, input = Input, output = Output,
              input_stream = InputStream, output_stream = OutputStream, opts = Opts
            }
          };
        false when length(ExportedArities) == 0 ->
          ?l_warning(#{
            text => "Handler module does not export required function",
            what => init_ets_table, result => error, details => #{
              function => lists:flatten(io_lib:format("~ts/~p", [FunctionName, 2]))
            }
          }),
          [];
        false ->
          ?l_warning(#{
            text => "Handler module exports required function with wrong arity",
            what => init_ets_table, result => error, details => #{
              function => lists:flatten(io_lib:format("~ts/~p", [FunctionName, 2])),
              actual_exports => lists:flatten(lists:join(",", [
                lists:flatten(io_lib:format("~ts/~p", [FunctionName, Arity]))
                || Arity <- ExportedArities
              ]))
            }
          }),
          []
      end
    end || #rpc{
      name = MethodName, input = Input, output = Output,
      input_stream = InputStream, output_stream = OutputStream, opts = Opts
    } <- Methods
  ]),
  ets:insert(S0#state.ets, MethodDefinitions).



atom_snake_case(Name) ->
  NameString = atom_to_list(Name),
  Snaked = lists:foldl(
    fun(RE, Snaking) ->
      re:replace(Snaking, RE, "\\1_\\2", [{return, list}, global])
    end, NameString,
    [
      "(.)([A-Z][a-z]+)",   %% uppercase followed by lowercase
      "(.)([0-9]+)",        %% any consecutive digits
      "([a-z0-9])([A-Z])"   %% uppercase with lowercase or digit before it
    ]
  ),
  Snaked1 = string:replace(Snaked, ".", "_", all),
  Snaked2 = string:replace(Snaked1, "__", "_", all),
  list_to_atom(string:to_lower(unicode:characters_to_list(Snaked2))).
