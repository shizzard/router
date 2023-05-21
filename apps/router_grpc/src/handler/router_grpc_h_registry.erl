-module(router_grpc_h_registry).

-include("router_grpc.hrl").
-include("router_grpc_service_registry.hrl").
-include("router_grpc_h_registry.hrl").
-include_lib("router_pb/include/registry_definitions.hrl").
-include_lib("router_log/include/router_log.hrl").

-export([
  init/2,
  register_virtual_service/2, unregister_virtual_service/2,
  enable_virtual_service_maintenance/2, disable_virtual_service_maintenance/2,
  list_virtual_services/2, control_stream/2
]).

-define(default_page_size, 20).
-define(max_page_size, 50).

-record(state, {
  conn_req :: cowboy_req:req(),
  definition_internal :: router_grpc:definition_internal(),
  definition_external :: router_grpc:definition_external() | undefined,
  session_id :: router_grpc_stream_h:session_id() | undefined,
  handler_pid :: pid() | undefined
}).
-type state() :: #state{}.



%% Metrics



%% gRPC endpoints



-spec init(
  Definition :: router_grpc:definition(),
  ConnReq :: cowboy_req:req()
) -> state().

init(Definition, ConnReq) ->
  #state{definition_internal = Definition, conn_req = ConnReq}.



-spec register_virtual_service(
  Pdu :: registry_definitions:'lg.service.router.RegisterVirtualServiceRq'(),
  S0 :: state()
) ->
  {ok, router_grpc_h:handler_ret_ok_reply_fin(PduT :: registry_definitions:'lg.service.router.RegisterVirtualServiceRs'()), S1 :: state()} |
  {error, router_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

register_virtual_service(#'lg.service.router.RegisterVirtualServiceRq'{
  virtual_service = #'lg.core.grpc.VirtualService'{
    service = {stateless, #'lg.core.grpc.VirtualService.StatelessVirtualService'{
      package = Package0, name = Name0, methods = Methods0
    }},
    maintenance_mode_enabled = MaintenanceMode0,
    endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
  }
}, S0) ->
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
      register_virtual_service_impl(stateless, Package, Name, Methods, undefined, MaintenanceMode, Host, Port, S0);
    _ ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, maps:from_list(ErrorList)}, S0}
  end;

register_virtual_service(#'lg.service.router.RegisterVirtualServiceRq'{
  virtual_service = #'lg.core.grpc.VirtualService'{
    service = {stateful, #'lg.core.grpc.VirtualService.StatefulVirtualService'{
      package = Package0, name = Name0, methods = Methods0, cmp = Cmp0
    }},
    maintenance_mode_enabled = MaintenanceMode0,
    endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
  }
}, S0) ->
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
      register_virtual_service_impl(stateful, Package, Name, Methods, Cmp, MaintenanceMode, Host, Port, S0);
    _ ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, maps:from_list(ErrorList)}, S0}
  end.



register_virtual_service_impl(Type, Package, Name, Methods, Cmp, MaintenanceMode, Host, Port, S0) ->
  case router_grpc_service_registry:register(Type, Package, Name, Methods, Cmp, MaintenanceMode, Host, Port) of
    {ok, _Definition} ->
      ?l_debug(#{
        text => "Virtual service registered", what => register_virtual_service,
        result => ok
      }),
      {ok, {reply_fin, #'lg.service.router.RegisterVirtualServiceRs'{}}, S0};
    {error, InvalidFields} ->
      Trailers = maps:from_list(lists:flatten([
        case Field of
          cmp -> {?trailer_cmp_invalid, ?trailer_cmp_invalid_message(Cmp)};
          _ -> []
        end || Field <- InvalidFields
      ])),
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

unregister_virtual_service(#'lg.service.router.UnregisterVirtualServiceRq'{
  virtual_service = #'lg.core.grpc.VirtualService'{
    service = Service,
    endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
  }
}, S0) ->
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
      {ok, {reply_fin, #'lg.service.router.UnregisterVirtualServiceRs'{}}, S0};
    _ ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, maps:from_list(ErrorList)}, S0}
  end.



-spec enable_virtual_service_maintenance(
  Pdu :: registry_definitions:'lg.service.router.EnableVirtualServiceMaintenanceRq'(),
  S0 :: state()
) ->
  {ok, router_grpc_h:handler_ret_ok_reply_fin(PduT :: registry_definitions:'lg.service.router.EnableVirtualServiceMaintenanceRs'()), S1 :: state()} |
  {error, router_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

enable_virtual_service_maintenance(#'lg.service.router.EnableVirtualServiceMaintenanceRq'{
  virtual_service = #'lg.core.grpc.VirtualService'{
    service = Service,
    endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
  }
}, S0) ->
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
      Fqsn = <<Package/binary, ".", Name/binary>>,
      ok = router_grpc_service_registry:set_maintenance(Fqsn, Host, Port, true),
      {ok, {reply_fin, #'lg.service.router.EnableVirtualServiceMaintenanceRs'{}}, S0};
    _ ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, maps:from_list(ErrorList)}, S0}
  end.



-spec disable_virtual_service_maintenance(
  Pdu :: registry_definitions:'lg.service.router.DisableVirtualServiceMaintenanceRq'(),
  S0 :: state()
) ->
  {ok, router_grpc_h:handler_ret_ok_reply_fin(PduT :: registry_definitions:'lg.service.router.DisableVirtualServiceMaintenanceRs'()), S1 :: state()} |
  {error, router_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

disable_virtual_service_maintenance(#'lg.service.router.DisableVirtualServiceMaintenanceRq'{
  virtual_service = #'lg.core.grpc.VirtualService'{
    service = Service,
    endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
  }
}, S0) ->
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
      {ok, {reply_fin, #'lg.service.router.DisableVirtualServiceMaintenanceRs'{}}, S0};
    _ ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, maps:from_list(ErrorList)}, S0}
  end.



-spec list_virtual_services(
  Pdu :: registry_definitions:'lg.service.router.ListVirtualServicesRq'(),
  S0 :: state()
) ->
  {ok, router_grpc_h:handler_ret_ok_reply_fin(PduT :: registry_definitions:'lg.service.router.ListVirtualServicesRs'()), S1 :: state()} |
  {error, router_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

list_virtual_services(#'lg.service.router.ListVirtualServicesRq'{
  filter_fq_service_name = FilterFqsn0,
  filter_endpoint = FilterEndpoint0,
  pagination_request = PaginationRequest0
}, S0) ->
  {FilterFqsnErrors, FilterFqsn} = validate_filter_fq_service_name(FilterFqsn0),
  {FilterEndpointErrors, {FilterHost, FilterPort}} = validate_filter_endpoint(FilterEndpoint0),
  {PaginationRequestErrors, {PageToken, PageSize}} = validate_pagination_request(PaginationRequest0),
  ErrorList = lists:flatten([
    FilterFqsnErrors, FilterEndpointErrors, PaginationRequestErrors
  ]),
  case ErrorList of
    [] ->
      list_virtual_services_impl(FilterFqsn, FilterHost, FilterPort, PageToken, PageSize, S0);
    _ ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, maps:from_list(ErrorList)}, S0}
  end.



list_virtual_services_impl(FilterFqsn, FilterHost, FilterPort, PageToken, PageSize, S0) ->
  Filters = maps:from_list(lists:flatten([
    case FilterFqsn of undefined -> []; _ -> {filter_fq_service_name, FilterFqsn} end,
    case {FilterHost, FilterPort} of {undefined, undefined} -> []; _ -> {filter_endpoint, {FilterHost, FilterPort}} end
  ])),
  case router_grpc_service_registry:get_list(Filters, PageToken, PageSize) of
    {ok, {Definitions, NextPageToken}} ->
      Services = lists:map(fun list_virtual_services_impl_map/1, Definitions),
      PaginationRs = case NextPageToken of
        undefined -> undefined;
        _ -> #'lg.core.trait.PaginationRs'{next_page_token = NextPageToken}
      end,
      {ok, {reply_fin, #'lg.service.router.ListVirtualServicesRs'{services = Services, pagination_response = PaginationRs}}, S0};
    {error, invalid_token} ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, #{
        ?trailer_pagination_request_page_token_invalid => ?trailer_pagination_request_page_token_invalid_message(PageToken)
      }}, S0}
  end.



list_virtual_services_impl_map(#router_grpc_service_registry_definition_external{
  type = stateless, package = Package, service_name = ServiceName,
  fq_service_name = Fqsn, methods = Methods, host = Host, port = Port
}) ->
    #'lg.core.grpc.VirtualService'{
      service = {stateless, #'lg.core.grpc.VirtualService.StatelessVirtualService'{
        package = Package,
        name = ServiceName,
        methods = [#'lg.core.grpc.VirtualService.Method'{name = MethodName} || MethodName <- Methods]
      }},
      maintenance_mode_enabled = router_grpc_service_registry:is_maintenance(Fqsn, Host, Port),
      endpoint = #'lg.core.network.Endpoint'{host = Host, port = Port}
    };

list_virtual_services_impl_map(#router_grpc_service_registry_definition_external{
  type = stateful, package = Package, service_name = ServiceName,
  fq_service_name = Fqsn, methods = Methods, cmp = Cmp, host = Host, port = Port
}) ->
    #'lg.core.grpc.VirtualService'{
      service = {stateful, #'lg.core.grpc.VirtualService.StatefulVirtualService'{
        package = Package,
        name = ServiceName,
        methods = [#'lg.core.grpc.VirtualService.Method'{name = MethodName} || MethodName <- Methods],
        cmp = Cmp
      }},
      maintenance_mode_enabled = router_grpc_service_registry:is_maintenance(Fqsn, Host, Port),
      endpoint = #'lg.core.network.Endpoint'{host = Host, port = Port}
    }.



-spec control_stream(
  Pdu :: registry_definitions:'lg.service.router.ControlStreamEvent'(),
  S0 :: state()
) ->
  {ok, router_grpc_h:handler_ret_ok_reply(PduT :: registry_definitions:'lg.service.router.ControlStreamEvent'()), S1 :: state()} |
  {error, router_grpc_h:handler_ret_error_grpc_error_trailers(GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal), S1 :: state()}.

%% Id field is empty, report an error
control_stream(#'lg.service.router.ControlStreamEvent'{
  id = undefined,
  event = {_EventType, _Event}
}, S0) ->
  {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, #{
    ?trailer_id_empty => ?trailer_id_empty_message(undefined)
  }}, S0};

%% Initial InitRq request: session id is undefined, handler pid is undefined
control_stream(#'lg.service.router.ControlStreamEvent'{
  id = IdRecord,
  event = {init_rq, #'lg.service.router.ControlStreamEvent.InitRq'{}} = Event
} = _Pdu, #state{session_id = undefined, handler_pid = undefined} = S0) ->
  case control_stream_event_handle(Event, S0) of
    {ok, {RetEvent, S1}} ->
      {ok, {reply, #'lg.service.router.ControlStreamEvent'{id = IdRecord, event = RetEvent}}, S1};
    {error, {Trailers, S1}} ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, Trailers}, S1}
  end;

%% Initial ResumeRq request: session id is undefined, handler pid is undefined
control_stream(#'lg.service.router.ControlStreamEvent'{
  id = IdRecord,
  event = {resume_rq, #'lg.service.router.ControlStreamEvent.ResumeRq'{}} = Event
} = _Pdu, #state{session_id = undefined, handler_pid = undefined} = S0) ->
  case control_stream_event_handle(Event, S0) of
    {ok, {RetEvent, S1}} ->
      {ok, {reply, #'lg.service.router.ControlStreamEvent'{id = IdRecord, event = RetEvent}}, S1};
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
    ?trailer_control_stream_reinit => ?trailer_control_stream_reinit_message_init(undefined)
  }}, S0};

%% Erroneous ResumeRq request: session is already established
control_stream(#'lg.service.router.ControlStreamEvent'{
  event = {resume_rq, #'lg.service.router.ControlStreamEvent.ResumeRq'{}}
} = _Pdu, S0) ->
  {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, #{
    ?trailer_control_stream_reinit => ?trailer_control_stream_reinit_message_resume(undefined)
  }}, S0};

%% All other events are handled within control_stream_event_handle/2
control_stream(#'lg.service.router.ControlStreamEvent'{
  id = IdRecord,
  event = Event
} = _Pdu, S0) ->
  case control_stream_event_handle(Event, S0) of
    {ok, {RetEvent, S1}} ->
      {ok, {reply, #'lg.service.router.ControlStreamEvent'{id = IdRecord, event = RetEvent}}, S1#state{}};
    {ok, {fin, RetEvent, S1}} ->
      {ok, {reply_fin, #'lg.service.router.ControlStreamEvent'{id = IdRecord, event = RetEvent}}, S1#state{}};
    {error, {Trailers, S1}} ->
      {error, {grpc_error, ?grpc_code_invalid_argument, ?grpc_message_invalid_argument_payload, Trailers}, S1}
  end.



%% Control stream handlers



control_stream_event_handle({init_rq, #'lg.service.router.ControlStreamEvent.InitRq'{
    virtual_service = #'lg.core.grpc.VirtualService'{
      service = {stateless, #'lg.core.grpc.VirtualService.StatelessVirtualService'{
        package = Package0,
        name = Name0,
        methods = Methods0
      }},
      maintenance_mode_enabled = MaintenanceMode0,
      endpoint = #'lg.core.network.Endpoint'{host = Host0, port = Port0}
    }
  }},
  #state{session_id = undefined, handler_pid = undefined} = S0
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
      control_stream_event_handle_register_service(
        stateless, Package, Name, Methods, undefined, MaintenanceMode, Host, Port, S0
      );
    _ ->
      {error, {maps:from_list(ErrorList), S0}}
  end;

control_stream_event_handle({init_rq, #'lg.service.router.ControlStreamEvent.InitRq'{
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
  }},
  #state{session_id = undefined, handler_pid = undefined} = S0
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
      control_stream_event_handle_register_service(
        stateful, Package, Name, Methods, Cmp, MaintenanceMode, Host, Port, S0
      );
    _ ->
      {error, {maps:from_list(ErrorList), S0}}
  end;

control_stream_event_handle({resume_rq, #'lg.service.router.ControlStreamEvent.ResumeRq'{
    session_id = SessionId0
  }},
  #state{session_id = undefined, handler_pid = undefined} = S0
) ->
  {SessionErrors, SessionId} = validate_session_id(SessionId0),
  ErrorList = lists:flatten([SessionErrors]),
  case ErrorList of
    [] ->
      case router_grpc_stream_sup:lookup_handler(SessionId) of
        {ok, HPid} ->
          control_stream_event_handle_session_resume(HPid, SessionId, S0);
        {error, undefined} ->
          {error, {
            #{?trailer_control_stream_session_expired => ?trailer_control_stream_session_expired_message(undefined)},
            S0
          }}
      end
    %% Session validation always returns empty list of errors
    % _ -> {error, {maps:from_list(ErrorList), S0}}
  end;

control_stream_event_handle({register_agent_rq, #'lg.service.router.ControlStreamEvent.RegisterAgentRq'{
    agent_id = AgentId0,
    agent_instance = AgentInstance0
  }},
  S0
) ->
  {AgentIdErrors, AgentId} = validate_agent_id(AgentId0),
  {AgentInstanceErrors, AgentInstance} = validate_agent_instance(AgentInstance0),
  ErrorList = lists:flatten([AgentIdErrors, AgentInstanceErrors]),
  case ErrorList of
    [] ->
      control_stream_event_handle_register_agent(AgentId, AgentInstance, S0);
    _ -> {error, {maps:from_list(ErrorList), S0}}
  end.



control_stream_event_handle_register_service(Type, Package, Name, Methods, Cmp, MaintenanceMode, Host, Port, S0) ->
  case router_grpc_service_registry:register(Type, Package, Name, Methods, Cmp, MaintenanceMode, Host, Port) of
    {ok, Definition} ->
      control_stream_event_handle_start_session(S0#state{definition_external = Definition});
    {error, InvalidFields} ->
      {ok, {
        fin,
        {init_rs, #'lg.service.router.ControlStreamEvent.InitRs'{
          result = #'lg.core.trait.Result'{
            status = 'ERROR_INVALID_ARGUMENT',
            error_message = ?control_stream_init_error_message_mismatched_virtual_service,
            error_meta = lists:flatten([case Field of
              cmp ->
                {
                  ?control_stream_init_error_message_mismatched_virtual_service_cmp,
                  ?control_stream_init_error_message_mismatched_virtual_service_cmp_message(Cmp)
                };
              _ -> []
            end || Field <- InvalidFields])
          }
        }},
        S0
      }}
  end.



control_stream_event_handle_start_session(S0) ->
  SessionId = list_to_binary(uuid:uuid_to_string(uuid:get_v4_urandom())),
  {ok, HPid} = router_grpc_stream_sup:start_handler(
    SessionId, S0#state.definition_internal, S0#state.definition_external, S0#state.conn_req
  ),
  {ok, {
    {init_rs, #'lg.service.router.ControlStreamEvent.InitRs'{
      session_id = SessionId, result = #'lg.core.trait.Result'{status = 'SUCCESS'}
    }},
    S0#state{session_id = SessionId, handler_pid = HPid}
  }}.


control_stream_event_handle_session_resume(HPid, SessionId, S0) ->
  case router_grpc_stream_sup:recover_handler(HPid, SessionId) of
    ok ->
      {ok, {
        {init_rs, #'lg.service.router.ControlStreamEvent.InitRs'{
          session_id = SessionId, result = #'lg.core.trait.Result'{status = 'SUCCESS'}
        }},
        S0#state{session_id = SessionId, handler_pid = HPid}
      }};
    {error, Reason} ->
      {error, {
        #{?trailer_control_stream_session_resume_failed => ?trailer_control_stream_session_resume_failed_message(Reason)},
        S0
      }}
  end.



control_stream_event_handle_register_agent(AgentId, AgentInstance, #state{
  definition_external = Definition, handler_pid = HPid
} = S0) ->
  case router_grpc_stream_h:register_agent(
    HPid, Definition#router_grpc_service_registry_definition_external.fq_service_name, AgentId, AgentInstance
  ) of
    {ok, {AgentId_, AgentInstance_}} ->
      {ok, {
        {register_agent_rs, #'lg.service.router.ControlStreamEvent.RegisterAgentRs'{
          agent_id = AgentId_,
          agent_instance = AgentInstance_,
          result = #'lg.core.trait.Result'{status = 'SUCCESS'}
        }},
        S0
      }};
    {error, conflict} ->
      {error, {#{
        ?trailer_conflict => ?trailer_conflict_message(
          Definition#router_grpc_service_registry_definition_external.fq_service_name, AgentId, AgentInstance
        )
      }, S0}};
    {error, {invalid_service, Fqsn, Host, Port}} ->
      {error, {#{
        ?trailer_service_invalid => ?trailer_service_invalid_message(Fqsn, Host, Port)
      }, S0}}
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



validate_session_id(SessionId) -> {[], SessionId}.



% validate_fq_service_name(undefined) ->
%   {
%     {?trailer_fq_service_name_empty, ?trailer_fq_service_name_empty_message(undefined)},
%     undefined
%   };

% validate_fq_service_name(Fqsn) -> {[], Fqsn}.



validate_agent_id(undefined) ->
  {
    {?trailer_agent_id_empty, ?trailer_agent_id_empty_message(undefined)},
    undefined
  };

validate_agent_id(Fqsn) -> {[], Fqsn}.



validate_agent_instance(AgentInstance) -> {[], AgentInstance}.
