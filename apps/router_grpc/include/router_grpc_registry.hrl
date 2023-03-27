-record(router_grpc_registry_definition, {
  id :: {binary(), binary()},
  details :: router_grpc_registry:details()
}).

-record(router_grpc_registry_definition_details_internal, {
  definition :: atom(),
  service :: binary(),
  method :: binary(),
  module :: atom(),
  function :: atom(),
  input :: atom(),
  output :: atom(),
  input_stream :: boolean(),
  output_stream :: boolean(),
  opts :: list()
}).

-define(details_type_stateless, stateless).
-define(details_type_stateful, stateful).

-record(router_grpc_registry_definition_details_external, {
  type = ?details_type_stateless :: ?details_type_stateless | ?details_type_stateful,
  service :: binary(),
  method :: binary(),
  maintenance :: boolean(),
  host :: binary(),
  port :: 1..65535
}).
