-module(user_default).

%% One-liner to collect all required headers:
%% for header in `find apps -type f -iname '*.hrl' | grep -v router_cli | sort`; do echo $header | sed -e 's|^/[^/]*/||'; done

-include_lib("apps/router_grpc/include/router_grpc.hrl").
-include_lib("apps/router_grpc/include/router_grpc_client.hrl").
-include_lib("apps/router_grpc/include/router_grpc_client_pool.hrl").
-include_lib("apps/router_grpc/include/router_grpc_h_registry.hrl").
-include_lib("apps/router_grpc/include/router_grpc_service_registry.hrl").
-include_lib("apps/router_log/include/router_log.hrl").
-include_lib("apps/router_pb/include/grpc_definitions.hrl").
-include_lib("apps/router_pb/include/network_definitions.hrl").
-include_lib("apps/router_pb/include/registry_definitions.hrl").
-include_lib("apps/router_pb/include/trait_definitions.hrl").
