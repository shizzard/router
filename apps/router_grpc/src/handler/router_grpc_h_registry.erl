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
  case call_register_virtual_service_map_validate(Pdu) of
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

handle_call(?call_list_virtual_services(_Pdu), _GenReplyTo, S0) ->
  {reply, {ok, {reply_fin, #'lg.service.router.ListVirtualServicesRs'{}}}, S0};

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



call_register_virtual_service_map_validate(
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
  {PackageErrors, Package} = call_register_virtual_service_map_validate_package(Package0),
  {NameErrors, Name} = call_register_virtual_service_map_validate_name(Name0),
  {MethodsErrors, Methods} = call_register_virtual_service_map_validate_methods(Methods0),
  {MaintenanceModeErrors, MaintenanceMode} = call_register_virtual_service_map_validate_maintenance_mode(MaintenanceMode0),
  {HostErrors, Host} = call_register_virtual_service_map_validate_host(Host0),
  {PortErrors, Port} = call_register_virtual_service_map_validate_port(Port0),
  ErrorList = [Error || Error <- lists:flatten([
    PackageErrors, NameErrors, MethodsErrors, MaintenanceModeErrors, HostErrors, PortErrors
  ]), Error /= undefined],
  case ErrorList of
    [] ->
      call_register_virtual_service_generate_details(?details_type_stateless, Package, Name, Methods, MaintenanceMode, Host, Port);
    _ ->
      {error, maps:from_list(ErrorList)}
  end.



call_register_virtual_service_generate_details(Type, Package, Name, Methods, MaintenanceMode, Host, Port) ->
  DetailsList = [#router_grpc_registry_definition_details_external{
    type = Type, service = <<Package/binary, ".", Name/binary>>, method = Method,
    maintenance = MaintenanceMode, host = Host, port = Port
  } || Method <- Methods],
  call_register_virtual_service_register(DetailsList).



call_register_virtual_service_register([]) -> ok;

call_register_virtual_service_register([Details | DetailsList]) ->
  ok = router_grpc_registry:register(Details),
  call_register_virtual_service_register(DetailsList).



call_register_virtual_service_map_validate_package(<<>>) ->
  ?l_dev(#{text => "Empty package"}),
  {{?trailer_package_empty, ?trailer_package_empty_message(<<>>)}, undefined};

call_register_virtual_service_map_validate_package(Package) ->
  case lists:member(Package, router_grpc_registry:restricted_packages()) of
    true ->
      ?l_dev(#{text => "Restricted package"}),
      {{?trailer_package_restricted, ?trailer_package_restricted_message(Package)}, undefined};
    false ->
      {undefined, Package}
  end.



call_register_virtual_service_map_validate_name(<<>>) ->
  ?l_dev(#{text => "Empty name"}),
  {{?trailer_name_empty, ?trailer_name_empty_message(<<>>)}, undefined};

call_register_virtual_service_map_validate_name(Name) ->
  {undefined, Name}.



call_register_virtual_service_map_validate_methods(Methods) ->
  Names = [Name || #'lg.core.grpc.VirtualService.Method'{name = Name} <- Methods],
  case lists:member(<<>>, Names) of
    true ->
      ?l_dev(#{text => "Empty method"}),
      {{?trailer_method_empty, ?trailer_method_empty_message(<<>>)}, undefined};
    false ->
      {undefined, Names}
  end.



call_register_virtual_service_map_validate_maintenance_mode(Boolean) -> {undefined, Boolean}.



call_register_virtual_service_map_validate_host(<<>>) ->
  ?l_dev(#{text => "Empty host"}),
  {{?trailer_host_empty, ?trailer_host_empty_message(<<>>)}, undefined};

call_register_virtual_service_map_validate_host(Host) ->
  {undefined, Host}.



call_register_virtual_service_map_validate_port(Port) when Port > 65535; Port =< 0 ->
  ?l_dev(#{text => "Invalid port"}),
  {{?trailer_port_invalid, ?trailer_port_invalid_message(Port)}, undefined};

call_register_virtual_service_map_validate_port(Port) ->
  {undefined, Port}.



init_prometheus_metrics() ->
  ok.
