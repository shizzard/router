-module(router_grpc_registry).
-behaviour(gen_server).

-compile([nowarn_untyped_record]).

-include("router_grpc_registry.hrl").
-include_lib("gpb/include/gpb.hrl").
-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").

-export([
  restricted_packages/0, register/6, lookup/1, lookup_internal/1, lookup_external/1, get_list/0,
  is_maintenance/1, set_maintenance/2
]).
-export([start_link/2, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(service_ets_key(Type, Path, Host, Port), {Type, Path, Host, Port}).
-define(persistent_term_key_internal(Path), {?MODULE, persistent_term_key_internal, Path}).
-define(
  persistent_term_key_external_maintenance(ServiceName),
  {?MODULE, persistent_term_key_external_maintenance, ServiceName}
).
-define(restricted_packages, [<<"lg.service.router">>]).

-record(state, {
  ets :: ets:tid()
}).
-type state() :: #state{}.

-type service_ets_key() :: ?service_ets_key(service_type(), service_name(), endpoint_host(), endpoint_port()).
-type service_type() :: stateless | stateful.
-type service_name() :: binary().
-type method_name() :: binary().
-type service_maintenance() :: boolean().
-type endpoint_host() :: binary().
-type endpoint_port() :: 0..65535.
-export_type([
  service_ets_key/0, service_type/0, service_name/0, method_name/0, service_maintenance/0,
  endpoint_host/0, endpoint_port/0
]).

-type definition() :: definition_internal() | definition_external().
-type definition_internal() :: #router_grpc_registry_definition_internal{}.
-type definition_external() :: #router_grpc_registry_definition_external{}.
-export_type([definition/0, definition_internal/0, definition_external/0]).



%% Messages

-define(
  call_register(Type, ServiceName, Methods, Maintenance, Host, Port),
  {call_register, Type, ServiceName, Methods, Maintenance, Host, Port}
).



%% Metrics

% -define(metric_gge_proxies_amount, router_proxy_registry_proxies_amount).



%% Interface



-spec restricted_packages() -> [binary(), ...].

restricted_packages() -> ?restricted_packages.



-spec register(
  Type :: service_type(),
  ServiceName :: service_name(),
  Methods :: [method_name(), ...],
  Maintenance :: service_maintenance(),
  Host :: endpoint_host(),
  Port :: endpoint_port()
) ->
  typr:generic_return(
    ErrorRet :: term()
  ).

register(Type, ServiceName, Methods, Maintenance, Host, Port) ->
  gen_server:call(?MODULE, ?call_register(Type, ServiceName, Methods, Maintenance, Host, Port)).



-spec lookup(Path :: binary()) ->
  typr:generic_return(
    OkRet :: definition(),
    ErrorRet :: undefined
  ).

lookup(Path) ->
  case lookup_internal(Path) of
    {error, undefined} -> lookup_external(Path);
    OkRet -> OkRet
  end.



-spec lookup_internal(Path :: binary()) ->
  typr:generic_return(
    OkRet :: definition_internal(),
    ErrorRet :: undefined
  ).

lookup_internal(Path) ->
  case persistent_term:get(?persistent_term_key_internal(Path), undefined) of
    undefined -> {error, undefined};
    Definition -> {ok, Definition}
  end.



-spec lookup_external(Path :: binary()) ->
  typr:generic_return(
    OkRet :: definition_external(),
    ErrorRet :: undefined
  ).

lookup_external(Path) ->
  case ets:match(?MODULE, #router_grpc_registry_definition_external{
    id = ?service_ets_key('_', Path, '_', '_'),
    type = '_', service = '_', methods = '_', host = '_', port = '_'
  }, 1) of
    '$end_of_table' -> {error, undefined};
    [Definition] -> {ok, Definition}
  end.



-spec get_list() ->
  typr:ok_return(
    OkRet :: [definition_external()]
  ).

get_list() ->
  Map = maps:from_list(
    [{Id, Definition} || #router_grpc_registry_definition_external{id = Id} = Definition <- ets:tab2list(?MODULE)]
  ),
  {ok, maps:values(Map)}.



-spec is_maintenance(ServiceName :: service_name()) ->
  Ret :: boolean().

is_maintenance(ServiceName) ->
  persistent_term:get(?persistent_term_key_external_maintenance(ServiceName), false).



-spec set_maintenance(ServiceName :: service_name(), Bool :: boolean()) ->
  Ret :: typr:ok_return().

set_maintenance(ServiceName, true) ->
  persistent_term:set(?persistent_term_key_external_maintenance(ServiceName), true);

set_maintenance(ServiceName, false) ->
  _ = persistent_term:erase(?persistent_term_key_external_maintenance(ServiceName)),
  ok.



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
      {keypos, #router_grpc_registry_definition_external.id}]
    )
  },
  init_internals(ServiceDefinitions, ServiceMap, S0),
  {ok, S0}.



%% Handlers



handle_call(?call_register(Type, ServiceName, Methods, Maintenance, Host, Port), _GenReplyTo, S0) ->
  lists:foreach(fun(MethodName) ->
    Path = <<"/", ServiceName/binary, "/", MethodName/binary>>,
    Id = ?service_ets_key(Type, Path, Host, Port),
    Definition = #router_grpc_registry_definition_external{
      id = Id, type = Type, service = ServiceName, methods = Methods, host = Host, port = Port
    },
    ets:insert(S0#state.ets, Definition)
  end, Methods),
  case Maintenance of
    true -> persistent_term:put(?persistent_term_key_external_maintenance(ServiceName), Maintenance);
    false -> ok
  end,
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



init_internals([], _ServiceMap, S0) -> {ok, S0};

init_internals([ServiceDefinition | ServiceDefinitions], ServiceMap, S0) ->
  ServiceNames = ServiceDefinition:get_service_names(),
  [init_internals_service(ServiceName, ServiceDefinition, ServiceMap, S0) || ServiceName <- ServiceNames],
  init_internals(ServiceDefinitions, ServiceMap, S0).



init_internals_service(ServiceName, ServiceDefinition, ServiceMap, S0) ->
  case maps:get(ServiceName, ServiceMap, undefined) of
    undefined -> ok;
    ModuleName ->
      {{service, ServiceName}, Methods} = ServiceDefinition:get_service_def(ServiceName),
      init_internals_service_methods(ServiceName, ServiceDefinition, Methods, ModuleName, S0)
  end.



init_internals_service_methods(ServiceName, ServiceDefinition, Methods, ModuleName, _S0) ->
  [
    begin
      %% Check if configured module exports corresponding function with arity 2
      FunctionName = atom_snake_case(MethodName),
      ModuleExports = ModuleName:module_info(exports),
      ExportedArities = proplists:get_all_values(FunctionName, ModuleExports),
      case lists:member(2, ExportedArities) of
        true ->
          ServiceNameBin = atom_to_binary(ServiceName),
          MethodNameBin = atom_to_binary(MethodName),
          PathBin = <<"/", ServiceNameBin/binary, "/", MethodNameBin/binary>>,
          Definition = #router_grpc_registry_definition_internal{
            definition = ServiceDefinition, service = ServiceNameBin, method = MethodNameBin,
            module = ModuleName, function = FunctionName, input = Input, output = Output,
            input_stream = InputStream, output_stream = OutputStream, opts = Opts
          },
          persistent_term:put(?persistent_term_key_internal(PathBin), Definition);
        false when length(ExportedArities) == 0 ->
          ?l_warning(#{
            text => "Handler module does not export required function",
            what => init_internals, result => error, details => #{
              function => lists:flatten(io_lib:format("~ts/~p", [FunctionName, 2]))
            }
          }),
          [];
        false ->
          ?l_warning(#{
            text => "Handler module exports required function with wrong arity",
            what => init_internals, result => error, details => #{
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
  ].



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
