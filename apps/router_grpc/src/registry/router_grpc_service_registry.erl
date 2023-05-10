-module(router_grpc_service_registry).
-behaviour(gen_server).

-compile([nowarn_untyped_record]).

-include("router_grpc_service_registry.hrl").
-include_lib("gpb/include/gpb.hrl").
-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").

-export([
  restricted_packages/0, register/7, register/8, unregister/5,
  lookup_fqmn/1, lookup_fqmn_internal/1, lookup_fqmn_external/1,
  lookup_fqsn/4,
  get_list/1, get_list/2, get_list/3, is_maintenance/3, set_maintenance/4
]).
-export([start_link/2, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(table_registry, router_grpc_service_registry_table_registry).
-define(table_lookup, router_grpc_service_registry_table_lookup).
-define(table_registry_key(Type, ServiceName, Host, Port), {Type, ServiceName, Host, Port}).
-define(table_lookup_key(Path), {Path}).
-define(persistent_term_key_internal(Path), {?MODULE, persistent_term_key_internal, Path}).
-define(
  persistent_term_key_external_maintenance(ServiceName, Host, Port),
  {?MODULE, persistent_term_key_external_maintenance, ServiceName, Host, Port}
).
-define(restricted_packages, [<<"lg.service.router">>]).

-record(state, {
  table_registry :: ets:tid(),
  table_lookup :: ets:tid()
}).
-type state() :: #state{}.

-type table_registry_key() :: ?table_registry_key(
  Type :: service_type(), ServiceName :: service_name(), Host :: endpoint_host(), Port :: endpoint_port()
).
-type table_lookup_key() :: ?table_lookup_key(Path :: fq_method_name()).
-type service_type() :: stateless | stateful.
-type service_package() :: binary().
-type service_name() :: binary().
-type fq_service_name() :: binary().
-type fq_method_name() :: binary().
-type method_name() :: binary().
-type service_maintenance() :: boolean().
-type endpoint_host() :: binary().
-type endpoint_port() :: 0..65535.
-export_type([
  table_registry_key/0, table_lookup_key/0, service_type/0, service_package/0, service_name/0,
  fq_service_name/0, fq_method_name/0, method_name/0, service_maintenance/0, endpoint_host/0, endpoint_port/0
]).

-type definition() :: definition_internal() | definition_external().
-type definition_internal() :: #router_grpc_service_registry_definition_internal{}.
-type definition_external() :: #router_grpc_service_registry_definition_external{}.
-export_type([definition/0, definition_internal/0, definition_external/0]).



%% Messages

-define(
  call_register_stateless(Type, Package, ServiceName, Methods, Maintenance, Host, Port),
  {call_register_stateless, Type, Package, ServiceName, Methods, Maintenance, Host, Port}
).
-define(
  call_register_stateful(Type, Package, ServiceName, Methods, Cmp, Maintenance, Host, Port),
  {call_register_stateful, Type, Package, ServiceName, Methods, Cmp, Maintenance, Host, Port}
).
-define(
  call_unregister(Type, Package, ServiceName, Host, Port),
  {call_unregister, Type, Package, ServiceName, Host, Port}
).



%% Metrics

% -define(metric_gge_proxies_amount, router_proxy_registry_proxies_amount).



%% Interface



-spec restricted_packages() -> [binary(), ...].

restricted_packages() -> ?restricted_packages.



-spec register(
  Type :: service_type(),
  Package :: service_package(),
  ServiceName :: service_name(),
  Methods :: [method_name(), ...],
  Maintenance :: service_maintenance(),
  Host :: endpoint_host(),
  Port :: endpoint_port()
) ->
  typr:generic_return(
    ErrorRet :: term()
  ).

register(stateless, Package, ServiceName, Methods, Maintenance, Host, Port) ->
  gen_server:call(?MODULE, ?call_register_stateless(stateless, Package, ServiceName, Methods, Maintenance, Host, Port)).



-spec register(
  Type :: service_type(),
  Package :: service_package(),
  ServiceName :: service_name(),
  Methods :: [method_name(), ...],
  Cmp :: registry_definitions:'lg.core.grpc.VirtualService.StatefulVirtualService.ConflictManagementPolicy'(),
  Maintenance :: service_maintenance(),
  Host :: endpoint_host(),
  Port :: endpoint_port()
) ->
  typr:generic_return(
    ErrorRet :: term()
  ).

register(stateful, Package, ServiceName, Methods, Cmp, Maintenance, Host, Port) ->
  gen_server:call(?MODULE, ?call_register_stateful(stateful, Package, ServiceName, Methods, Cmp, Maintenance, Host, Port)).



-spec unregister(
  Type :: service_type(),
  Package :: service_package(),
  ServiceName :: service_name(),
  Host :: endpoint_host(),
  Port :: endpoint_port()
) ->
  typr:generic_return(
    ErrorRet :: term()
  ).

unregister(Type, Package, ServiceName, Host, Port) ->
  gen_server:call(?MODULE, ?call_unregister(Type, Package, ServiceName, Host, Port)).



-spec lookup_fqmn(Fqmn :: fq_method_name()) ->
  typr:generic_return(
    OkRet :: [definition(), ...],
    ErrorRet :: undefined
  ).

lookup_fqmn(Fqmn) ->
  case lookup_fqmn_internal(Fqmn) of
    {error, undefined} -> lookup_fqmn_external(Fqmn);
    OkRet -> OkRet
  end.



-spec lookup_fqmn_internal(Fqmn :: fq_method_name()) ->
  typr:generic_return(
    OkRet :: [definition_internal(), ...],
    ErrorRet :: undefined
  ).

lookup_fqmn_internal(Fqmn) ->
  case persistent_term:get(?persistent_term_key_internal(Fqmn), undefined) of
    undefined -> {error, undefined};
    Definition -> {ok, [Definition]}
  end.



-spec lookup_fqmn_external(Fqmn :: fq_method_name()) ->
  typr:generic_return(
    OkRet :: [definition_external(), ...],
    ErrorRet :: undefined
  ).

lookup_fqmn_external(Fqmn) ->
  case ets:lookup(?table_lookup, ?table_lookup_key(Fqmn)) of
    [] -> {error, undefined};
    Definitions -> {ok, Definitions}
  end.



-spec lookup_fqsn(
  Package :: service_type(),
  ServiceName :: fq_service_name(),
  Host :: endpoint_host(),
  Port :: endpoint_port()
) ->
  typr:generic_return(
    OkRet :: [definition_external()],
    ErrorRet :: undefined
  ).

lookup_fqsn(Type, FqServiceName, Host, Port) ->
  case ets:lookup(?table_registry, ?table_registry_key(Type, FqServiceName, Host, Port)) of
    [] -> {error, undefined};
    Definitions -> {ok, Definitions}
  end.



-spec get_list(PageSize :: pos_integer()) ->
  typr:generic_return(
    OkRet :: {List :: [definition_external()], NextPageToken :: router_grpc_pagination:page_token() | undefined},
    ErrorRet :: invalid_token
  ).

get_list(PageSize) -> get_list(#{}, undefined, PageSize).



-spec get_list(
  PageTokenOrFilters :: router_grpc_pagination:page_token() | undefined | #{atom() => term()},
  PageSize :: pos_integer()
) ->
  typr:generic_return(
    OkRet :: {List :: [definition_external()], NextPageToken :: router_grpc_pagination:page_token() | undefined},
    ErrorRet :: invalid_token
  ).

get_list(PageToken, PageSize) when is_binary(PageToken) ->
  get_list(#{}, PageToken, PageSize);

get_list(Filters, PageSize) when is_map(Filters) ->
  get_list(Filters, undefined, PageSize).



-spec get_list(
  Filters :: #{atom() => term()},
  PageToken :: router_grpc_pagination:page_token() | undefined,
  PageSize :: pos_integer()
) ->
  typr:generic_return(
    OkRet :: {List :: [definition_external()], NextPageToken :: router_grpc_pagination:page_token() | undefined},
    ErrorRet :: invalid_token
  ).

get_list(Filters, PageToken, PageSize) ->
  MatchSpecFun = get_list_match_spec_fun(
    maps:get(filter_fq_service_name, Filters, undefined),
    maps:get(filter_endpoint, Filters, {undefined, undefined})
  ),
  case router_grpc_pagination:get_list(?table_registry, MatchSpecFun, fun key_take/1, PageToken, PageSize) of
    {ok, {final_page, List}} ->
      {ok, {List, undefined}};
    {ok, {page, List, NextPageToken}} ->
      {ok, {List, NextPageToken}};
    {ok, empty} ->
      {ok, {[], undefined}};
    {error, invalid_token} ->
      {error, invalid_token}
  end.



-spec is_maintenance(FqServiceName :: fq_service_name(), Host :: endpoint_host(), Port :: endpoint_port()) ->
  Ret :: boolean().

is_maintenance(FqServiceName, Host, Port) ->
  persistent_term:get(?persistent_term_key_external_maintenance(FqServiceName, Host, Port), false).



-spec set_maintenance(
  FqServiceName :: fq_service_name(), Host :: endpoint_host(), Port :: endpoint_port(), Bool :: boolean()
) ->
  Ret :: typr:ok_return().

set_maintenance(FqServiceName, Host, Port, true) ->
  persistent_term:put(?persistent_term_key_external_maintenance(FqServiceName, Host, Port), true);

set_maintenance(FqServiceName, Host, Port, false) ->
  _ = persistent_term:erase(?persistent_term_key_external_maintenance(FqServiceName, Host, Port)),
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
    table_registry = ets:new(?table_registry,
      [ordered_set, protected, named_table, {read_concurrency, true},
      {keypos, #router_grpc_service_registry_definition_external.id}]
    ),
    table_lookup = ets:new(?table_lookup,
      [duplicate_bag, protected, named_table, {read_concurrency, true},
      {keypos, #router_grpc_service_registry_definition_external.id}]
    )
  },
  init_internals(ServiceDefinitions, ServiceMap, S0),
  {ok, S0}.



%% Handlers



handle_call(?call_register_stateless(Type, Package, ServiceName, Methods, Maintenance, Host, Port), _GenReplyTo, S0) ->
  FqServiceName = <<Package/binary, ".", ServiceName/binary>>,
  RegistryId = ?table_registry_key(Type, FqServiceName, Host, Port),
  RegistryDefinition = #router_grpc_service_registry_definition_external{
    id = RegistryId, type = Type, package = Package, service = ServiceName,
    fq_service = FqServiceName, methods = Methods, host = Host, port = Port
  },
  case ets:insert_new(S0#state.table_registry, RegistryDefinition) of
    true ->
      lists:foreach(fun(MethodName) ->
        Fqmn = <<"/", FqServiceName/binary, "/", MethodName/binary>>,
        LookupId = ?table_lookup_key(Fqmn),
        LookupDefinition = RegistryDefinition#router_grpc_service_registry_definition_external{id = LookupId},
        ets:insert(S0#state.table_lookup, LookupDefinition)
      end, Methods),
      case Maintenance of
        true -> set_maintenance(ServiceName, Host, Port, Maintenance);
        false -> ok
      end,
      {reply, ok, S0};
    false ->
      {reply, ok, S0}
  end;

handle_call(?call_register_stateful(Type, Package, ServiceName, Methods, Cmp, Maintenance, Host, Port), _GenReplyTo, S0) ->
  FqServiceName = <<Package/binary, ".", ServiceName/binary>>,
  RegistryId = ?table_registry_key(Type, FqServiceName, Host, Port),
  RegistryDefinition = #router_grpc_service_registry_definition_external{
    id = RegistryId, type = Type, package = Package, service = ServiceName,
    fq_service = FqServiceName, methods = Methods, cmp = Cmp, host = Host, port = Port
  },
  case ets:insert_new(S0#state.table_registry, RegistryDefinition) of
    true ->
      lists:foreach(fun(MethodName) ->
        Fqmn = <<"/", FqServiceName/binary, "/", MethodName/binary>>,
        LookupId = ?table_lookup_key(Fqmn),
        LookupDefinition = RegistryDefinition#router_grpc_service_registry_definition_external{id = LookupId},
        ets:insert(S0#state.table_lookup, LookupDefinition)
      end, Methods),
      case Maintenance of
        true -> set_maintenance(ServiceName, Host, Port, Maintenance);
        false -> ok
      end,
      {reply, ok, S0};
    false ->
      {reply, ok, S0}
  end;

handle_call(?call_unregister(Type, Package, ServiceName, Host, Port), _GenReplyTo, S0) ->
  handle_call_unregister(Type, Package, ServiceName, Host, Port, S0);

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



%% This function causes dialyzer error regarding record construction:
%% > Record construction
%% > #router_grpc_service_registry_definition_external{... :: '_'}
%% > violates the declared type of ...
-dialyzer({nowarn_function, [handle_call_unregister/6]}).
handle_call_unregister(Type, Package, ServiceName, Host, Port, S0) ->
  FqServiceName = <<Package/binary, ".", ServiceName/binary>>,
  true = ets:delete(S0#state.table_registry, ?table_registry_key(Type, FqServiceName, Host, Port)),
  true = ets:match_delete(S0#state.table_lookup, #router_grpc_service_registry_definition_external{
    service = ServiceName, host = Host, port = Port, _ = '_'
  }),
  {reply, ok, S0}.



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
          Definition = #router_grpc_service_registry_definition_internal{
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



%% This function causes dialyzer error regarding record construction:
%% > Record construction
%% > #router_grpc_service_registry_definition_external{... :: '_'}
%% > violates the declared type of ...
-dialyzer({nowarn_function, [get_list_match_spec_fun/2]}).

% ets:fun2ms(
%   fun(#router_grpc_service_registry_definition_external{id = Id, _ = '_'} = Obj)
%   when Id >= Key ->
%     Obj
%   end
% )
get_list_match_spec_fun(undefined, {undefined, undefined}) ->
  fun(Key) ->
    [{
      #router_grpc_service_registry_definition_external{id = '$1', _ = '_'},
      [{'>=', '$1', {const,Key}}],
      ['$_']
    }]
  end;

% ets:fun2ms(
%   fun(#router_grpc_service_registry_definition_external{
%     id = Id, fq_service = Fqsn, _ = '_'
%   } = Obj)
%   when Id >= Key, Fqsn == FqFilter ->
%     Obj
%   end
% )
get_list_match_spec_fun(FqFilter, {undefined, undefined}) ->
  fun(Key) ->
    [{#router_grpc_service_registry_definition_external{id = '$1', fq_service = '$2', _ = '_'},
      [{'>=', '$1', {const,Key}}, {'==', '$2', {const,FqFilter}}],
      ['$_']
    }]
  end;

% ets:fun2ms(
%   fun(#router_grpc_service_registry_definition_external{
%     id = Id, host = Host_, port = Port_, _ = '_'
%   } = Obj)
%   when Id >= Key, Host == Host_, Port == Port_ ->
%     Obj
%   end
% )
get_list_match_spec_fun(undefined, {Host, Port}) ->
  fun(Key) ->
    [{#router_grpc_service_registry_definition_external{id = '$1', host = '$2', port = '$3', _ = '_'},
      [{'>=', '$1', {const,Key}}, {'==', {const,Host}, '$2'}, {'==', {const,Port}, '$3'}],
      ['$_']
    }]
  end;

% ets:fun2ms(
%   fun(#router_grpc_service_registry_definition_external{
%     id = Id, fq_service = Fqsn, host = Host_, port = Port_, _ = '_'
%   } = Obj)
%   when Id >= Key, Fqsn == FqFilter, Host == Host_, Port == Port_ ->
%     Obj
%   end
% )
get_list_match_spec_fun(FqFilter, {Host, Port}) ->
  fun(Key) ->
    [{#router_grpc_service_registry_definition_external{
      id = '$1', fq_service = '$2', host = '$3', port = '$4', _ = '_'},
      [{'>=', '$1', {const,Key}}, {'==', '$2', {const,FqFilter}}, {'==', {const,Host}, '$3'}, {'==', {const,Port}, '$4'}],
      ['$_']
    }]
  end.



key_take(#router_grpc_service_registry_definition_external{id = Id}) -> Id.
