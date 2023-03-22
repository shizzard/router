-record(router_grpc_registry_definition, {
  id :: {atom(), atom()},
  definition :: atom(),
  service :: atom(),
  method :: atom(),
  module :: atom(),
  function :: atom(),
  input :: atom(),
  output :: atom(),
  input_stream :: boolean(),
  output_stream :: boolean(),
  opts :: list()
}).
