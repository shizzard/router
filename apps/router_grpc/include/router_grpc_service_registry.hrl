-record(router_grpc_service_registry_definition_internal, {
  definition :: atom(),
  service_name :: router_grpc:service_name(),
  method :: router_grpc:method_name(),
  module :: atom(),
  function :: atom(),
  input :: atom(),
  output :: atom(),
  input_stream :: boolean(),
  output_stream :: boolean(),
  opts :: list()
}).

-record(router_grpc_service_registry_definition_external, {
  id :: router_grpc_service_registry:table_registry_key(),
  type :: router_grpc:service_type(),
  package :: router_grpc:service_package(),
  service_name :: router_grpc:service_name(),
  fq_service_name :: router_grpc:fq_service_name(),
  methods :: [router_grpc:method_name(), ...],
  cmp = 'PREEMPTIVE' :: registry_definitions:'lg.core.grpc.VirtualService.StatefulVirtualService.ConflictManagementPolicy'(),
  host :: router_grpc:endpoint_host(),
  port :: router_grpc:endpoint_port()
}).
