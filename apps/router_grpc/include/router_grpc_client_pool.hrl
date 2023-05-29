-define(router_grpc_client_pool_gproc_key(Module, Definition), {
  Module,
  Definition#router_grpc_service_registry_definition_external.fq_service_name,
  Definition#router_grpc_service_registry_definition_external.host,
  Definition#router_grpc_service_registry_definition_external.port
}).
