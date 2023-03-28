-module(router_grpc_h_registry).
-behaviour(gen_server).

-include("router_grpc.hrl").
-include("router_grpc_registry.hrl").
-include("router_grpc_h_registry.hrl").
-include_lib("router_pb/include/registry_definitions.hrl").
-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").

-export([
  register_virtual_service/2, unregister_virtual_service/2,
  enable_virtual_service_maintenance/2, disable_virtual_service_maintenance/2,
  list_virtual_services/2, control_stream/2
]).
-export([
  start_link/0, init/1,
  handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3
]).

-define(handler_mode_unary, handler_mode_unary).
-define(handler_mode_unistream_from, handler_mode_unistream_from).
-define(handler_mode_unistream_to, handler_mode_unistream_to).
-define(handler_mode_bistream, handler_mode_bistream).
-type handler_mode() ::
  ?handler_mode_unary | ?handler_mode_unistream_from |
  ?handler_mode_unistream_to | ?handler_mode_bistream.

-record(state, {
  handler_mode = ?handler_mode_unary :: handler_mode()
}).
-type state() :: #state{}.

-export_type([]).



%% Messages

-define(call_register_virtual_service(Pdu), {register_virtual_service, Pdu}).
-define(call_unregister_virtual_service(Pdu), {unregister_virtual_service, Pdu}).
-define(call_enable_virtual_service_maintenance(Pdu), {enable_virtual_service_maintenance, Pdu}).
-define(call_disable_virtual_service_maintenance(Pdu), {disable_virtual_service_maintenance, Pdu}).
-define(call_list_virtual_services(Pdu), {list_virtual_services, Pdu}).
-define(call_control_stream(Pdu), {control_stream, Pdu}).



%% Metrics



%% gRPC endpoints



-spec register_virtual_service(
  Pid :: pid(),
  Pdu :: registry_definitions:'lg.service.router.RegisterVirtualServiceRq'()
) ->
  router_grpc_h:handler_ret(
    PduT :: undefined,
    PduFinT :: registry_definitions:'lg.service.router.RegisterVirtualServiceRs'(),
    GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal
  ).

register_virtual_service(Pid, Pdu) ->
  gen_server:call(Pid, ?call_register_virtual_service(Pdu)).



-spec unregister_virtual_service(
  Pid :: pid(),
  Pdu :: registry_definitions:'lg.service.router.UnregisterVirtualServiceRq'()
) ->
  router_grpc_h:handler_ret(
    PduT :: undefined,
    PduFinT :: registry_definitions:'lg.service.router.UnregisterVirtualServiceRs'(),
    GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal
  ).

unregister_virtual_service(Pid, Pdu) ->
  gen_server:call(Pid, ?call_unregister_virtual_service(Pdu)).



-spec enable_virtual_service_maintenance(
  Pid :: pid(),
  Pdu :: registry_definitions:'lg.service.router.EnableVirtualServiceMaintenanceRq'()
) ->
  router_grpc_h:handler_ret(
    PduT :: undefined,
    PduFinT :: registry_definitions:'lg.service.router.EnableVirtualServiceMaintenanceRs'(),
    GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal
  ).

enable_virtual_service_maintenance(Pid, Pdu) ->
  gen_server:call(Pid, ?call_enable_virtual_service_maintenance(Pdu)).



-spec disable_virtual_service_maintenance(
  Pid :: pid(),
  Pdu :: registry_definitions:'lg.service.router.DisableVirtualServiceMaintenanceRq'()
) ->
  router_grpc_h:handler_ret(
    PduT :: undefined,
    PduFinT :: registry_definitions:'lg.service.router.DisableVirtualServiceMaintenanceRs'(),
    GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal
  ).

disable_virtual_service_maintenance(Pid, Pdu) ->
  gen_server:call(Pid, ?call_disable_virtual_service_maintenance(Pdu)).



-spec list_virtual_services(
  Pid :: pid(),
  Pdu :: registry_definitions:'lg.service.router.ListVirtualServicesRq'()
) ->
  router_grpc_h:handler_ret(
    PduT :: undefined,
    PduFinT :: registry_definitions:'lg.service.router.ListVirtualServicesRs'(),
    GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal
  ).

list_virtual_services(Pid, Pdu) ->
  gen_server:call(Pid, ?call_list_virtual_services(Pdu)).



-spec control_stream(
  Pid :: pid(),
  Pdu :: registry_definitions:'lg.service.router.ControlStreamEvent'()
) ->
  router_grpc_h:handler_ret(
    PduT :: registry_definitions:'lg.service.router.ControlStreamEvent'(),
    PduFinT :: undefined,
    GrpcCodeT :: ?grpc_code_internal
  ).

control_stream(Pid, Pdu) ->
  gen_server:call(Pid, ?call_control_stream(Pdu)).



%% Interface



-spec start_link() ->
  typr:ok_return(OkRet :: pid()).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).



init([]) ->
  router_log:component(router_grpc_h),
  ok = quickrand:seed(),
  ok = init_prometheus_metrics(),
  S0 = #state{},
  {ok, S0}.



%% Handlers



handle_call(?call_register_virtual_service(Pdu), _GenReplyTo, S0) ->
  case call_register_virtual_service_validate(Pdu) of
    ok ->
      ?l_debug(#{
        text => "Virtual service registered", what => call_register_virtual_service,
        result => ok
      }),
      {reply, {ok, {reply_fin, #'lg.service.router.RegisterVirtualServiceRs'{}}}, S0};
    {error, Trailers} ->
      ?l_debug(#{
        text => "Failed to register virtual service", what => call_register_virtual_service,
        result => error, details => #{trailers => Trailers}
      }),
      {reply, {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, Trailers}}, S0}
  end;

handle_call(?call_unregister_virtual_service(_Pdu), _GenReplyTo, S0) ->
  {reply, {ok, {reply_fin, #'lg.service.router.UnregisterVirtualServiceRs'{}}}, S0};

handle_call(?call_enable_virtual_service_maintenance(_Pdu), _GenReplyTo, S0) ->
  {reply, {ok, {reply_fin, #'lg.service.router.EnableVirtualServiceMaintenanceRs'{}}}, S0};

handle_call(?call_disable_virtual_service_maintenance(_Pdu), _GenReplyTo, S0) ->
  {reply, {ok, {reply_fin, #'lg.service.router.DisableVirtualServiceMaintenanceRs'{}}}, S0};

handle_call(?call_list_virtual_services(Pdu), _GenReplyTo, S0) ->
  case call_list_virtual_services_validate(Pdu) of
    {ok, RetPdu} ->
      {reply, {ok, {reply_fin, RetPdu}}, S0};
    {error, Trailers} ->
      {reply, {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, Trailers}}, S0}
  end;

handle_call(?call_control_stream(_Pdu), _GenReplyTo, S0) ->
  {reply, {ok, wait}, S0};

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



call_register_virtual_service_validate(
  #'lg.service.router.RegisterVirtualServiceRq'{
    virtual_service = #'lg.core.grpc.VirtualService'{
      service = {stateless, #'lg.core.grpc.VirtualService.StatelessVirtualService'{
        package = Package0,
        name = Name0,
        methods = Methods0
      }},
      maintenance_mode_enabled = MaintenanceMode0,
      endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
    }
  }
) ->
  {PackageErrors, Package} = validate_package(Package0),
  {NameErrors, Name} = validate_name(Name0),
  {MethodsErrors, Methods} = validate_methods(Methods0),
  {MaintenanceModeErrors, MaintenanceMode} = validate_maintenance_mode(MaintenanceMode0),
  {HostErrors, Host} = validate_host(Host0),
  {PortErrors, Port} = validate_port(Port0),
  ErrorList = [Error || Error <- lists:flatten([
    PackageErrors, NameErrors, MethodsErrors, MaintenanceModeErrors, HostErrors, PortErrors
  ]), Error /= undefined],
  case ErrorList of
    [] ->
      ServiceName = <<Package/binary, ".", Name/binary>>,
      ok = router_grpc_registry:register(stateless, ServiceName, Methods, MaintenanceMode, Host, Port);
    _ ->
      {error, maps:from_list(ErrorList)}
  end.



call_list_virtual_services_validate(#'lg.service.router.ListVirtualServicesRq'{
  filter_fq_service_name = FilterFqServiceName0,
  filter_endpoint = FilterEndpoint0,
  pagination_request = PaginationRequest0
}) ->
  {FilterFqServiceNameErrors, FilterFqServiceName} = validate_filter_fq_service_name(FilterFqServiceName0),
  {FilterEndpointErrors, {FilterHost, FilterPort}} = validate_filter_endpoint(FilterEndpoint0),
  {PaginationRequestErrors, PaginationRequest} = validate_pagination_request(PaginationRequest0),
  ErrorList = [Error || Error <- lists:flatten([
    FilterFqServiceNameErrors, FilterEndpointErrors, PaginationRequestErrors
  ]), Error /= undefined],
  case ErrorList of
    [] ->
      call_list_virtual_services_filter(FilterFqServiceName, FilterHost, FilterPort, PaginationRequest);
    _ ->
      {error, maps:from_list(ErrorList)}
  end.



call_list_virtual_services_filter(FilterFqServiceName, FilterHost, FilterPort, _PaginationRequest) ->
  {ok, Definitions0} = router_grpc_registry:get_list(),
  Definitions1 = call_list_virtual_services_filter_fq_service_name(FilterFqServiceName, Definitions0),
  Definitions2 = call_list_virtual_services_filter_endpoint(FilterHost, FilterPort, Definitions1),
  Services = lists:map(fun call_list_virtual_services_map/1, Definitions2),
  {ok, #'lg.service.router.ListVirtualServicesRs'{services = Services}}.



%% Filters and maps



call_list_virtual_services_filter_fq_service_name(undefined, Definitions) -> Definitions;

call_list_virtual_services_filter_fq_service_name(FilterFqServiceName, Definitions) ->
  [
    Definition || #router_grpc_registry_definition_external{service = ServiceName} = Definition
    <- Definitions, ServiceName == FilterFqServiceName
  ].



call_list_virtual_services_filter_endpoint(undefined, undefined, Definitions) -> Definitions;

call_list_virtual_services_filter_endpoint(FilterHost, FilterPort, Definitions) ->
  [
    Definition || #router_grpc_registry_definition_external{host = Host, port = Port} = Definition
    <- Definitions, Host == FilterHost, Port == FilterPort
  ].



call_list_virtual_services_map(#router_grpc_registry_definition_external{
  type = stateless, service = ServiceName, methods = Methods, host = Host, port = Port
}) ->
    #'lg.core.grpc.VirtualService'{
      service = {stateless, #'lg.core.grpc.VirtualService.StatelessVirtualService'{
        methods = [#'lg.core.grpc.VirtualService.Method'{name = MethodName} || MethodName <- Methods]
      }},
      maintenance_mode_enabled = router_grpc_registry:is_maintenance(ServiceName),
      endpoint = #'lg.core.network.Endpoint'{host = Host, port = Port}
    }.



%% Validators



validate_package(<<>>) ->
  ?l_dev(#{text => "Empty package"}),
  {{?trailer_package_empty, ?trailer_package_empty_message(<<>>)}, undefined};

validate_package(Package) ->
  case lists:member(Package, router_grpc_registry:restricted_packages()) of
    true ->
      ?l_dev(#{text => "Restricted package"}),
      {{?trailer_package_restricted, ?trailer_package_restricted_message(Package)}, undefined};
    false ->
      {undefined, Package}
  end.



validate_name(<<>>) ->
  ?l_dev(#{text => "Empty name"}),
  {{?trailer_name_empty, ?trailer_name_empty_message(<<>>)}, undefined};

validate_name(Name) ->
  {undefined, Name}.



validate_methods(Methods) ->
  Names = [Name || #'lg.core.grpc.VirtualService.Method'{name = Name} <- Methods],
  case lists:member(<<>>, Names) of
    true ->
      ?l_dev(#{text => "Empty method"}),
      {{?trailer_method_empty, ?trailer_method_empty_message(<<>>)}, undefined};
    false ->
      {undefined, Names}
  end.



validate_maintenance_mode(Boolean) -> {undefined, Boolean}.



validate_host(<<>>) ->
  ?l_dev(#{text => "Empty host"}),
  {{?trailer_host_empty, ?trailer_host_empty_message(<<>>)}, undefined};

validate_host(Host) ->
  {undefined, Host}.



validate_port(Port) when Port > 65535; Port =< 0 ->
  ?l_dev(#{text => "Invalid port"}),
  {{?trailer_port_invalid, ?trailer_port_invalid_message(Port)}, undefined};

validate_port(Port) ->
  {undefined, Port}.



validate_filter_fq_service_name(<<>>) -> {undefined, undefined};

validate_filter_fq_service_name(Filter) -> {undefined, Filter}.



validate_filter_endpoint(undefined) ->
  {undefined, {undefined, undefined}};

validate_filter_endpoint(#'lg.core.network.Endpoint'{host = FilterHost0, port = FilterPort0}) ->
  case {FilterHost0, FilterPort0} of
    %% Filter disabled
    {<<>>, 0} ->
      {undefined, {undefined, undefined}};
    %% Host empty, port invalid
    {<<>>, FilterPort} when FilterPort > 65535, FilterPort =< 0 ->
      {
        [
          {?trailer_filter_endpoint_host_empty, ?trailer_filter_endpoint_host_empty_message(<<>>)},
          {?trailer_filter_endpoint_port_invalid, ?trailer_filter_endpoint_port_invalid_message(FilterPort)}
        ],
        {undefined, undefined}
      };
    %% Host empty, port valid
    {<<>>, _FilterPort} ->
      {
        {?trailer_filter_endpoint_host_empty, ?trailer_filter_endpoint_host_empty_message(<<>>)},
        {undefined, undefined}
      };
    %% Host valid, port invalid
    {FilterHost, FilterPort} when FilterHost /= <<>>, FilterPort > 65535, FilterPort =< 0 ->
      {
        {?trailer_filter_endpoint_port_invalid, ?trailer_filter_endpoint_port_invalid_message(FilterPort)},
        {undefined, undefined}
      };
    %% Filter enabled
    {FilterHost, FilterPort} ->
      {undefined, {FilterHost, FilterPort}}
  end.



validate_pagination_request(undefined) ->
  {undefined, undefined};

validate_pagination_request(_) ->
  {
    {?trailer_pagination_request_not_implemented, ?trailer_pagination_request_not_implemented_message(undefined)},
    undefined
  }.



init_prometheus_metrics() ->
  ok.
