-module(router_grpc_h_registry).

-include("router_grpc.hrl").
-include("router_grpc_service_registry.hrl").
-include("router_grpc_h_registry.hrl").
-include_lib("router_pb/include/registry_definitions.hrl").
-include_lib("router_log/include/router_log.hrl").

-export([
  init/0,
  register_virtual_service/2, unregister_virtual_service/2,
  enable_virtual_service_maintenance/2, disable_virtual_service_maintenance/2,
  list_virtual_services/2, control_stream/2
]).

-define(default_page_size, 20).
-define(max_page_size, 50).

-record(state, {
  session_id :: router_grpc_stream_h:session_id() | undefined,
  handler_pid :: pid() | undefined
}).
-type state() :: #state{}.



%% Metrics



%% gRPC endpoints



-spec init() -> state().

init() ->
  #state{}.



-spec register_virtual_service(
  Pdu :: registry_definitions:'lg.service.router.RegisterVirtualServiceRq'(),
  S0 :: state()
) ->
  {ok, router_grpc_h:handler_ret_ok_reply_fin(PduT :: registry_definitions:'lg.service.router.RegisterVirtualServiceRs'()), S1 :: state()} |
  {error, router_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

register_virtual_service(Pdu, S0) ->
  case register_virtual_service_handle(Pdu) of
    {ok, RetPdu} ->
      ?l_info(#{
        text => "Virtual service registered", what => register_virtual_service,
        result => ok
      }),
      {ok, {reply_fin, RetPdu}, S0};
    {error, Trailers} ->
      ?l_debug(#{
        text => "Failed to register virtual service", what => register_virtual_service,
        result => error, details => #{trailers => Trailers}
      }),
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, Trailers}, S0}
  end.



-spec unregister_virtual_service(
  Pdu :: registry_definitions:'lg.service.router.UnregisterVirtualServiceRq'(),
  S0 :: state()
) ->
  {ok, router_grpc_h:handler_ret_ok_reply_fin(PduT :: registry_definitions:'lg.service.router.UnregisterVirtualServiceRs'()), S1 :: state()} |
  {error, router_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

unregister_virtual_service(Pdu, S0) ->
  case unregister_virtual_service_handle(Pdu) of
    {ok, RetPdu} ->
      ?l_info(#{
        text => "Virtual service unregistered", what => unregister_virtual_service,
        result => ok
      }),
      {ok, {reply_fin, RetPdu}, S0};
    {error, Trailers} ->
      ?l_debug(#{
        text => "Failed to unregister virtual service", what => unregister_virtual_service,
        result => error, details => #{trailers => Trailers}
      }),
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, Trailers}, S0}
  end.



-spec enable_virtual_service_maintenance(
  Pdu :: registry_definitions:'lg.service.router.EnableVirtualServiceMaintenanceRq'(),
  S0 :: state()
) ->
  {ok, router_grpc_h:handler_ret_ok_reply_fin(PduT :: registry_definitions:'lg.service.router.EnableVirtualServiceMaintenanceRs'()), S1 :: state()} |
  {error, router_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

enable_virtual_service_maintenance(Pdu, S0) ->
  case enable_virtual_service_maintenance_handle(Pdu) of
    {ok, RetPdu} ->
      ?l_info(#{
        text => "Virtual service maintenance mode set", what => enable_virtual_service_maintenance,
        result => ok
      }),
      {ok, {reply_fin, RetPdu}, S0};
    {error, Trailers} ->
      ?l_debug(#{
        text => "Failed to set virtual service maintenance mode", what => enable_virtual_service_maintenance,
        result => error, details => #{trailers => Trailers}
      }),
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, Trailers}, S0}
  end.



-spec disable_virtual_service_maintenance(
  Pdu :: registry_definitions:'lg.service.router.DisableVirtualServiceMaintenanceRq'(),
  S0 :: state()
) ->
  {ok, router_grpc_h:handler_ret_ok_reply_fin(PduT :: registry_definitions:'lg.service.router.DisableVirtualServiceMaintenanceRs'()), S1 :: state()} |
  {error, router_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

disable_virtual_service_maintenance(Pdu, S0) ->
  case disable_virtual_service_maintenance_handle(Pdu) of
    {ok, RetPdu} ->
      ?l_info(#{
        text => "Virtual service maintenance mode unset", what => disable_virtual_service_maintenance,
        result => ok
      }),
      {ok, {reply_fin, RetPdu}, S0};
    {error, Trailers} ->
      ?l_debug(#{
        text => "Failed to unset virtual service maintenance mode", what => unregister_virtual_service,
        result => error, details => #{trailers => Trailers}
      }),
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, Trailers}, S0}
  end.



-spec list_virtual_services(
  Pdu :: registry_definitions:'lg.service.router.ListVirtualServicesRq'(),
  S0 :: state()
) ->
  {ok, router_grpc_h:handler_ret_ok_reply_fin(PduT :: registry_definitions:'lg.service.router.ListVirtualServicesRs'()), S1 :: state()} |
  {error, router_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

list_virtual_services(Pdu, S0) ->
  case list_virtual_services_handle(Pdu) of
    {ok, RetPdu} ->
      {ok, {reply_fin, RetPdu}, S0};
    {error, Trailers} ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, Trailers}, S0}
  end.



-spec control_stream(
  Pdu :: registry_definitions:'lg.service.router.ControlStreamEvent'(),
  S0 :: state()
) ->
  {ok, router_grpc_h:handler_ret_ok_reply(PduT :: registry_definitions:'lg.service.router.ControlStreamEvent'()), S1 :: state()} |
  {error, router_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

%% Initial InitRq request: session id is undefined, handler pid is undefined
control_stream(#'lg.service.router.ControlStreamEvent'{
  event = {init_rq, #'lg.service.router.ControlStreamEvent.InitRq'{}}
} = Pdu, #state{session_id = undefined, handler_pid = undefined} = S0) ->
  case control_stream_handle(Pdu, S0) of
    {ok, {RetPdu, S1}} ->
      {ok, {reply, RetPdu}, S1};
    {error, {Trailers, S1}} ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, Trailers}, S1}
  end;

%% No initial InitRq request: session id is undefined, handler pid is undefined
control_stream(_Pdu, #state{session_id = undefined, handler_pid = undefined} = S0) ->
  {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, #{
    ?trailer_control_stream_noinit => ?trailer_control_stream_noinit_message(undefined)
  }}, S0};

%% Erroneous InitRq request: session is already established
control_stream(#'lg.service.router.ControlStreamEvent'{
  event = {init_rq, #'lg.service.router.ControlStreamEvent.InitRq'{}}
} = _Pdu, S0) ->
  {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, #{
    ?trailer_control_stream_reinit => ?trailer_control_stream_reinit_message(undefined)
  }}, S0};

%% RegisterVirtualService event, stateful variant
control_stream(#'lg.service.router.ControlStreamEvent'{
  event = {register_virtual_service_rq, #'lg.service.router.ControlStreamEvent.RegisterVirtualServiceRq'{}}
} = Pdu, S0) ->
  case control_stream_handle(Pdu, S0) of
    {ok, {RetPdu, S1}} ->
      {ok, {reply, RetPdu}, S1#state{}};
    {error, {Trailers, S1}} ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, Trailers}, S1}
  end.



%% Internals



register_virtual_service_handle(
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
  ErrorList = lists:flatten([
    PackageErrors, NameErrors, MethodsErrors, MaintenanceModeErrors, HostErrors, PortErrors
  ]),
  case ErrorList of
    [] ->
      ok = router_grpc_service_registry:register(stateless, Package, Name, Methods, MaintenanceMode, Host, Port),
      {ok, #'lg.service.router.RegisterVirtualServiceRs'{}};
    _ ->
      {error, maps:from_list(ErrorList)}
  end;

register_virtual_service_handle(
  #'lg.service.router.RegisterVirtualServiceRq'{
    virtual_service = #'lg.core.grpc.VirtualService'{
      service = {stateful, #'lg.core.grpc.VirtualService.StatefulVirtualService'{
        package = Package0,
        name = Name0,
        methods = Methods0,
        cmp = Cmp0
      }},
      maintenance_mode_enabled = MaintenanceMode0,
      endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
    }
  }
) ->
  {PackageErrors, Package} = validate_package(Package0),
  {NameErrors, Name} = validate_name(Name0),
  {MethodsErrors, Methods} = validate_methods(Methods0),
  {CmpErrors, Cmp} = validate_cmp(Cmp0),
  {MaintenanceModeErrors, MaintenanceMode} = validate_maintenance_mode(MaintenanceMode0),
  {HostErrors, Host} = validate_host(Host0),
  {PortErrors, Port} = validate_port(Port0),
  ErrorList = lists:flatten([
    PackageErrors, NameErrors, MethodsErrors, CmpErrors, MaintenanceModeErrors, HostErrors, PortErrors
  ]),
  case ErrorList of
    [] ->
      ok = router_grpc_service_registry:register(stateful, Package, Name, Methods, Cmp, MaintenanceMode, Host, Port),
      {ok, #'lg.service.router.RegisterVirtualServiceRs'{}};
    _ ->
      {error, maps:from_list(ErrorList)}
  end.



unregister_virtual_service_handle(#'lg.service.router.UnregisterVirtualServiceRq'{
  virtual_service = #'lg.core.grpc.VirtualService'{
    service = Service,
    endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
  }
}) ->
  {Type, Package0, ServiceName0} = case Service of
    {stateless, #'lg.core.grpc.VirtualService.StatelessVirtualService'{
      package = Package00,
      name = ServiceName00
    }} -> {stateless, Package00, ServiceName00};
    {stateful, #'lg.core.grpc.VirtualService.StatefulVirtualService'{
      package = Package00,
      name = ServiceName00
    }} -> {stateful, Package00, ServiceName00}
  end,
  {PackageErrors, Package} = validate_package(Package0),
  {ServiceNameErrors, ServiceName} = validate_name(ServiceName0),
  {HostErrors, Host} = validate_host(Host0),
  {PortErrors, Port} = validate_port(Port0),
  ErrorList = lists:flatten([
    PackageErrors, ServiceNameErrors, HostErrors, PortErrors
  ]),
  case ErrorList of
    [] ->
      ok = router_grpc_service_registry:unregister(Type, Package, ServiceName, Host, Port),
      {ok, #'lg.service.router.UnregisterVirtualServiceRs'{}};
    _ ->
      {error, maps:from_list(ErrorList)}
  end.



enable_virtual_service_maintenance_handle(#'lg.service.router.EnableVirtualServiceMaintenanceRq'{
  virtual_service = #'lg.core.grpc.VirtualService'{
    service = Service,
    endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
  }
}) ->
  {_Type, Package0, Name0} = case Service of
    {stateless, #'lg.core.grpc.VirtualService.StatelessVirtualService'{
      package = Package00,
      name = Name00
    }} -> {stateless, Package00, Name00};
    {stateful, #'lg.core.grpc.VirtualService.StatefulVirtualService'{
      package = Package00,
      name = Name00
    }} -> {stateful, Package00, Name00}
  end,
  {PackageErrors, Package} = validate_package(Package0),
  {NameErrors, Name} = validate_name(Name0),
  {HostErrors, Host} = validate_host(Host0),
  {PortErrors, Port} = validate_port(Port0),
  ErrorList = lists:flatten([
    PackageErrors, NameErrors, HostErrors, PortErrors
  ]),
  case ErrorList of
    [] ->
      ServiceName = <<Package/binary, ".", Name/binary>>,
      ok = router_grpc_service_registry:set_maintenance(ServiceName, Host, Port, true),
      {ok, #'lg.service.router.EnableVirtualServiceMaintenanceRs'{}};
    _ ->
      {error, maps:from_list(ErrorList)}
  end.



disable_virtual_service_maintenance_handle(#'lg.service.router.DisableVirtualServiceMaintenanceRq'{
  virtual_service = #'lg.core.grpc.VirtualService'{
    service = Service,
    endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
  }
}) ->
  {_Type, Package0, Name0} = case Service of
    {stateless, #'lg.core.grpc.VirtualService.StatelessVirtualService'{
      package = Package00,
      name = Name00
    }} -> {stateless, Package00, Name00};
    {stateful, #'lg.core.grpc.VirtualService.StatefulVirtualService'{
      package = Package00,
      name = Name00
    }} -> {stateful, Package00, Name00}
  end,
  {PackageErrors, Package} = validate_package(Package0),
  {NameErrors, Name} = validate_name(Name0),
  {HostErrors, Host} = validate_host(Host0),
  {PortErrors, Port} = validate_port(Port0),
  ErrorList = lists:flatten([
    PackageErrors, NameErrors, HostErrors, PortErrors
  ]),
  case ErrorList of
    [] ->
      ServiceName = <<Package/binary, ".", Name/binary>>,
      ok = router_grpc_service_registry:set_maintenance(ServiceName, Host, Port, false),
      {ok, #'lg.service.router.DisableVirtualServiceMaintenanceRs'{}};
    _ ->
      {error, maps:from_list(ErrorList)}
  end.



list_virtual_services_handle(#'lg.service.router.ListVirtualServicesRq'{
  filter_fq_service_name = FilterFqServiceName0,
  filter_endpoint = FilterEndpoint0,
  pagination_request = PaginationRequest0
}) ->
  {FilterFqServiceNameErrors, FilterFqServiceName} = validate_filter_fq_service_name(FilterFqServiceName0),
  {FilterEndpointErrors, {FilterHost, FilterPort}} = validate_filter_endpoint(FilterEndpoint0),
  {PaginationRequestErrors, {PageToken, PageSize}} = validate_pagination_request(PaginationRequest0),
  ErrorList = lists:flatten([
    FilterFqServiceNameErrors, FilterEndpointErrors, PaginationRequestErrors
  ]),
  case ErrorList of
    [] ->
      list_virtual_services_list(FilterFqServiceName, FilterHost, FilterPort, PageToken, PageSize);
    _ ->
      {error, maps:from_list(ErrorList)}
  end.



list_virtual_services_list(FilterFqServiceName, FilterHost, FilterPort, PageToken, PageSize) ->
  Filters = maps:from_list(lists:flatten([
    case FilterFqServiceName of undefined -> []; _ -> {filter_fq_service_name, FilterFqServiceName} end,
    case {FilterHost, FilterPort} of {undefined, undefined} -> []; _ -> {filter_endpoint, {FilterHost, FilterPort}} end
  ])),
  case router_grpc_service_registry:get_list(Filters, PageToken, PageSize) of
    {ok, {Definitions, NextPageToken}} ->
      Services = lists:map(fun list_virtual_services_list_map/1, Definitions),
      PaginationRs = case NextPageToken of
        undefined -> undefined;
        _ -> #'lg.core.trait.PaginationRs'{next_page_token = NextPageToken}
      end,
      {ok, #'lg.service.router.ListVirtualServicesRs'{services = Services, pagination_response = PaginationRs}};
    {error, invalid_token} ->
      {error, #{
        ?trailer_pagination_request_page_token_invalid => ?trailer_pagination_request_page_token_invalid_message(PageToken)
      }}
  end.



list_virtual_services_list_map(#router_grpc_service_registry_definition_external{
  type = stateless, package = Package, service = ServiceName,
  fq_service = FqServiceName, methods = Methods, host = Host, port = Port
}) ->
    #'lg.core.grpc.VirtualService'{
      service = {stateless, #'lg.core.grpc.VirtualService.StatelessVirtualService'{
        package = Package,
        name = ServiceName,
        methods = [#'lg.core.grpc.VirtualService.Method'{name = MethodName} || MethodName <- Methods]
      }},
      maintenance_mode_enabled = router_grpc_service_registry:is_maintenance(FqServiceName, Host, Port),
      endpoint = #'lg.core.network.Endpoint'{host = Host, port = Port}
    };

list_virtual_services_list_map(#router_grpc_service_registry_definition_external{
  type = stateful, package = Package, service = ServiceName,
  fq_service = FqServiceName, methods = Methods, cmp = Cmp, host = Host, port = Port
}) ->
    #'lg.core.grpc.VirtualService'{
      service = {stateful, #'lg.core.grpc.VirtualService.StatefulVirtualService'{
        package = Package,
        name = ServiceName,
        methods = [#'lg.core.grpc.VirtualService.Method'{name = MethodName} || MethodName <- Methods],
        cmp = Cmp
      }},
      maintenance_mode_enabled = router_grpc_service_registry:is_maintenance(FqServiceName, Host, Port),
      endpoint = #'lg.core.network.Endpoint'{host = Host, port = Port}
    }.



control_stream_handle(#'lg.service.router.ControlStreamEvent'{
  event = {init_rq, #'lg.service.router.ControlStreamEvent.InitRq'{
    id = IdRecord0, session_id = <<>>,
    endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
  }}
}, S0) ->
  {IdRecordErrors, IdRecord} = validate_id(IdRecord0),
  % {SessionErrors, <<>>} = validate_session_id(SessionId0),
  {HostErrors, Host} = validate_host(Host0),
  {PortErrors, Port} = validate_port(Port0),
  ErrorList = lists:flatten([IdRecordErrors, HostErrors, PortErrors]),
  case ErrorList of
    [] ->
      SessionId = list_to_binary(uuid:uuid_to_string(uuid:get_v4_urandom())),
      {ok, HPid} = router_grpc_stream_sup:start_handler(SessionId, Host, Port),
      {ok, {#'lg.service.router.ControlStreamEvent'{
        event = {init_rs, #'lg.service.router.ControlStreamEvent.InitRs'{
          id = IdRecord, session_id = SessionId, result = #'lg.core.trait.Result'{status = 'SUCCESS'}
        }}
      }, S0#state{session_id = SessionId, handler_pid = HPid}}};
    Trailers -> {error, {Trailers, S0}}
  end;

control_stream_handle(#'lg.service.router.ControlStreamEvent'{
  event = {register_virtual_service_rq, #'lg.service.router.ControlStreamEvent.RegisterVirtualServiceRq'{
    id = IdRecord0,
    virtual_service = #'lg.core.grpc.VirtualService'{
      service = {stateless, #'lg.core.grpc.VirtualService.StatelessVirtualService'{
        package = Package0,
        name = Name0,
        methods = Methods0
      }},
      maintenance_mode_enabled = MaintenanceMode0,
      endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
    }
  }}
}, S0) ->
  {IdRecordErrors, IdRecord} = validate_id(IdRecord0),
  {PackageErrors, Package} = validate_package(Package0),
  {NameErrors, Name} = validate_name(Name0),
  {MethodsErrors, Methods} = validate_methods(Methods0),
  {MaintenanceModeErrors, MaintenanceMode} = validate_maintenance_mode(MaintenanceMode0),
  {HostErrors, Host} = validate_host(Host0),
  {PortErrors, Port} = validate_port(Port0),
  ErrorList = lists:flatten([
    IdRecordErrors, PackageErrors, NameErrors, MethodsErrors, MaintenanceModeErrors, HostErrors, PortErrors
  ]),
  case ErrorList of
    [] ->
      ok = router_grpc_service_registry:register(stateless, Package, Name, Methods, MaintenanceMode, Host, Port),
      {ok, {#'lg.service.router.ControlStreamEvent'{
        event = {register_virtual_service_rs, #'lg.service.router.ControlStreamEvent.RegisterVirtualServiceRs'{
          id = IdRecord, result = #'lg.core.trait.Result'{status = 'SUCCESS'}
        }}
      }, S0}};
    Trailers -> {error, {Trailers, S0}}
  end;

control_stream_handle(#'lg.service.router.ControlStreamEvent'{
  event = {register_virtual_service_rq, #'lg.service.router.ControlStreamEvent.RegisterVirtualServiceRq'{
    id = IdRecord0,
    virtual_service = #'lg.core.grpc.VirtualService'{
      service = {stateful, #'lg.core.grpc.VirtualService.StatefulVirtualService'{
        package = Package0,
        name = Name0,
        methods = Methods0,
        cmp = Cmp0
      }},
      maintenance_mode_enabled = MaintenanceMode0,
      endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
    }
  }}
}, S0) ->
  {IdRecordErrors, IdRecord} = validate_id(IdRecord0),
  {PackageErrors, Package} = validate_package(Package0),
  {NameErrors, Name} = validate_name(Name0),
  {MethodsErrors, Methods} = validate_methods(Methods0),
  {CmpErrors, Cmp} = validate_cmp(Cmp0),
  {MaintenanceModeErrors, MaintenanceMode} = validate_maintenance_mode(MaintenanceMode0),
  {HostErrors, Host} = validate_host(Host0),
  {PortErrors, Port} = validate_port(Port0),
  ErrorList = lists:flatten([
    IdRecordErrors, PackageErrors, NameErrors, MethodsErrors, CmpErrors, MaintenanceModeErrors, HostErrors, PortErrors
  ]),
  case ErrorList of
    [] ->
      ok = router_grpc_service_registry:register(stateful, Package, Name, Methods, Cmp, MaintenanceMode, Host, Port),
      {ok, {#'lg.service.router.ControlStreamEvent'{
        event = {register_virtual_service_rs, #'lg.service.router.ControlStreamEvent.RegisterVirtualServiceRs'{
          id = IdRecord, result = #'lg.core.trait.Result'{status = 'SUCCESS'}
        }}
      }, S0}};
    Trailers -> {error, Trailers}
  end.



%% Validators



validate_package(<<>>) ->
  {{?trailer_package_empty, ?trailer_package_empty_message(<<>>)}, undefined};

validate_package(Package) ->
  case lists:member(Package, router_grpc_service_registry:restricted_packages()) of
    true ->
      {{?trailer_package_restricted, ?trailer_package_restricted_message(Package)}, undefined};
    false ->
      {[], Package}
  end.



validate_name(<<>>) ->
  {{?trailer_name_empty, ?trailer_name_empty_message(<<>>)}, undefined};

validate_name(Name) ->
  {[], Name}.



validate_methods(Methods) ->
  Names = [Name || #'lg.core.grpc.VirtualService.Method'{name = Name} <- Methods],
  case lists:member(<<>>, Names) of
    true ->
      {{?trailer_method_empty, ?trailer_method_empty_message(<<>>)}, undefined};
    false ->
      {[], Names}
  end.



validate_cmp(Cmp) -> {[], Cmp}.



validate_maintenance_mode(Boolean) -> {[], Boolean}.



validate_host(<<>>) ->
  {{?trailer_host_empty, ?trailer_host_empty_message(<<>>)}, undefined};

validate_host(Host) ->
  {[], Host}.



validate_port(Port) when Port > 65535; Port =< 0 ->
  {{?trailer_port_invalid, ?trailer_port_invalid_message(Port)}, undefined};

validate_port(Port) ->
  {[], Port}.



validate_filter_fq_service_name(<<>>) -> {[], undefined};

validate_filter_fq_service_name(Filter) -> {[], Filter}.



validate_filter_endpoint(undefined) ->
  {[], {undefined, undefined}};

validate_filter_endpoint(#'lg.core.network.Endpoint'{host = FilterHost0, port = FilterPort0}) ->
  case {FilterHost0, FilterPort0} of
    %% Filter disabled
    {<<>>, 0} ->
      {[], {undefined, undefined}};
    %% Host empty, port invalid
    {<<>>, FilterPort} when FilterPort > 65535 orelse FilterPort =< 0 ->
      {
        [
          {?trailer_filter_endpoint_host_empty, ?trailer_filter_endpoint_host_empty_message(<<>>)},
          {?trailer_filter_endpoint_port_invalid, ?trailer_filter_endpoint_port_invalid_message(FilterPort)}
        ],
        {[], undefined}
      };
    %% Host empty, port valid
    {<<>>, _FilterPort} ->
      {
        {?trailer_filter_endpoint_host_empty, ?trailer_filter_endpoint_host_empty_message(<<>>)},
        {[], undefined}
      };
    %% Host valid, port invalid
    {FilterHost, FilterPort} when FilterHost /= <<>>, (FilterPort > 65535 orelse FilterPort =< 0) ->
      {
        {?trailer_filter_endpoint_port_invalid, ?trailer_filter_endpoint_port_invalid_message(FilterPort)},
        {[], undefined}
      };
    %% Filter enabled
    {FilterHost, FilterPort} ->
      {[], {FilterHost, FilterPort}}
  end.



validate_pagination_request(undefined) ->
  {[], {undefined, ?default_page_size}};

validate_pagination_request(#'lg.core.trait.PaginationRq'{
  page_token = <<>>, page_size = PageSize
}) ->
  case PageSize of
    N when N =< 0 -> {
      {?trailer_pagination_request_page_size_invalid, ?trailer_pagination_request_page_size_invalid_message(PageSize)},
      {undefined, ?default_page_size}
    };
    N when N > 0 orelse N =< ?max_page_size -> {[], {undefined, N}};
    N when N > ?max_page_size -> {[], {undefined, ?max_page_size}}
  end;

validate_pagination_request(#'lg.core.trait.PaginationRq'{
  page_token = PageToken, page_size = 0
}) ->
  {[], {PageToken, ?default_page_size}};

validate_pagination_request(#'lg.core.trait.PaginationRq'{
  page_token = PageToken, page_size = PageSize
}) ->
  {[], {PageToken, PageSize}}.



validate_id(undefined) ->
  {
    {?trailer_id_empty, ?trailer_id_empty_message(undefined)},
    undefined
  };

validate_id(#'lg.core.trait.Id'{id = Id} = IdRecord) when byte_size(Id) > 0 -> {[], IdRecord}.



% validate_session_id(SessionId) -> {undefined, SessionId}.
