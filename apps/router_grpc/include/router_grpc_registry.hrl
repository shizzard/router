-record(router_grpc_registry_definition_internal, {
  definition :: atom(),
  service :: router_grpc_registry:service_name(),
  method :: router_grpc_registry:method_name(),
  module :: atom(),
  function :: atom(),
  input :: atom(),
  output :: atom(),
  input_stream :: boolean(),
  output_stream :: boolean(),
  opts :: list()
}).

-record(router_grpc_registry_definition_external, {
  id :: router_grpc_registry:service_ets_key(),
  type :: router_grpc_registry:service_type(),
  service :: router_grpc_registry:service_name(),
  methods :: [router_grpc_registry:method_name(), ...],
  host :: router_grpc_registry:endpoint_host(),
  port :: router_grpc_registry:endpoint_port()
}).
