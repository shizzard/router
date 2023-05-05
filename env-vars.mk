RELX_REPLACE_OS_VARS ?= true
ROUTER_VMARGS_SNAME ?= router
ROUTER_VMARGS_COOKIE ?= router
ROUTER_VMARGS_LIMIT_ETS ?= 1024
ROUTER_VMARGS_LIMIT_PROCESSES ?= 100000
ROUTER_VMARGS_LIMIT_PORTS ?= 10000
ROUTER_VMARGS_LIMIT_ATOMS ?= 100000
ROUTER_VMARGS_ASYNC_THREADS ?= 8
ROUTER_VMARGS_KERNEL_POLL ?= true
ROUTER_APP_LOGGER_LOG_ROOT ?= $(ROUTER_DIR_LOGS)
ROUTER_APP_LOGGER_LOG_LEVEL ?= debug

ROUTER_APP_HASHRING_BUCKETS_PO2 ?= 4
ROUTER_APP_HASHRING_NODES_PO2 ?= 2
ROUTER_APP_GRPC_LISTENER_PORT ?= 8137
ROUTER_APP_GRPC_SESSION_INACTIVITY_LIMIT_MS ?= 15000
