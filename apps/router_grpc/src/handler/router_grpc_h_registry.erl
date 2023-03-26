-module(router_grpc_h_registry).
-behaviour(gen_server).

-include("router_grpc.hrl").
-include("router_grpc_registry.hrl").
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

-record(state, {
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
    GrpcCodeT :: ?grpc_code_invalid_argument | ?grpc_code_internal
  ).

control_stream(Pid, Pdu) ->
  gen_server:call(Pid, ?call_control_stream(Pdu)).



%% Interface



-spec start_link() ->
  typr:ok_return(OkRet :: pid()).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).



init([]) ->
  envoy_log:component(router_grpc_h),
  ok = quickrand:seed(),
  ok = init_prometheus_metrics(),
  S0 = #state{},
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
