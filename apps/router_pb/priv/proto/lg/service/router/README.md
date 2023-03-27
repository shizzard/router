# Router Service

## Concepts

The Router service employs several key concepts:

- **Virtual Service**: A virtual service represents a single gRPC service,
  identified by a combination of package and service name. Each virtual service
  instance can be further identified by a combination of package, service name,
  network endpoint, and additional metadata used for routing requests and
  responses. Virtual services come in two types: stateless and stateful.
  Stateless services do not maintain any global persistent state that requires
  concurrent access, while stateful services maintain such state and must
  manage long-running actors that provide concurrent access to this state.

- **Agent**: An agent is an actor within a stateful service. Each agent has a
  parent virtual service, an ID, and an instance ID. This addressing schema
  will be referred to as the
  `<actor_id>@<fq_virtual_service_name>/<actor_instance>` notation throughout
  this document.

- **Unary RPC, Unidirectional Stream, Bidirectional Stream**: These concepts
  refer to the corresponding
  [gRPC core concepts](https://grpc.io/docs/what-is-grpc/core-concepts/) with
  the same names.

##
