%% See router_grpc_external_context.erl

-record(router_grpc_external_context, {
  agent_id :: router_grpc:agent_id() | undefined,
  agent_instance :: router_grpc:agent_instance() | undefined,
  request_id :: router_grpc:request_id() | undefined
}).
