-record(router_grpc_service_registry_definition_internal, {
  definition :: atom(),
  service :: router_grpc_service_registry:service_name(),
  method :: router_grpc_service_registry:method_name(),
  module :: atom(),
  function :: atom(),
  input :: atom(),
  output :: atom(),
  input_stream :: boolean(),
  output_stream :: boolean(),
  opts :: list()
}).

-record(router_grpc_service_registry_definition_external, {
  id :: router_grpc_service_registry:table_registry_key() | router_grpc_service_registry:table_lookup_key(),
  type :: router_grpc_service_registry:service_type(),
  package :: router_grpc_service_registry:service_package(),
  service :: router_grpc_service_registry:service_name(),
  fq_service :: router_grpc_service_registry:fq_service_name(),
  methods :: [router_grpc_service_registry:method_name(), ...],
  cmp = 'PREEMPTIVE' :: registry_definitions:'lg.core.grpc.VirtualService.StatefulVirtualService.ConflictManagementPolicy'(),
  host :: router_grpc_service_registry:endpoint_host(),
  port :: router_grpc_service_registry:endpoint_port()
}).
