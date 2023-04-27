-module(user_default).

-include_lib("router_grpc/include/router_grpc_client.hrl").
-include_lib("router_grpc/include/router_grpc_h_registry.hrl").
-include_lib("router_grpc/include/router_grpc_service_registry.hrl").
-include_lib("router_grpc/include/router_grpc.hrl").

-include_lib("router_log/include/router_log.hrl").

-include_lib("router_pb/include/grpc_definitions.hrl").
-include_lib("router_pb/include/network_definitions.hrl").
-include_lib("router_pb/include/registry_definitions.hrl").
-include_lib("router_pb/include/trait_definitions.hrl").
