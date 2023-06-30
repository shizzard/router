################################################################################
# Prepare

.EXPORT_ALL_VARIABLES:
.ONESHELL:
.DELETE_ON_ERROR:
.SHELLFLAGS := -eu -o pipefail -c
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
SHELL := bash

################################################################################
# Directories

RTGW_DIR_ROOT := $(abspath ./)
RTGW_DIR_APPS := $(RTGW_DIR_ROOT)/apps
RTGW_DIR_CONFIG := $(RTGW_DIR_ROOT)/config
RTGW_DIR_BUILD := $(RTGW_DIR_ROOT)/_build
RTGW_DIR_LOGS := $(RTGW_DIR_ROOT)/_logs

REQUIRED_DIRS =
_MKDIRS := $(shell for d in $(REQUIRED_DIRS); do \
		[[ -d $$d ]] || mkdir -p $$d; \
	done)

################################################################################
# Required executables

ERLC := $(shell which erlc)
DOCKER := $(shell which docker)
ifeq (, $(ERLC))
$(warning "No erlc found, is erlang installed?")
endif
ifeq (, $(DOCKER))
$(warning "No docker found, is it installed?")
endif

define print_app_env
	@printenv | grep ^RTGW | grep -v print_app_env
endef

include env-vars.mk

################################################################################
# Default target

RELEASE_BIN := $(RTGW_DIR_BUILD)/default/rel/rtgw/bin/rtgw

RTGW_SOURCE := $(shell find $(RTGW_DIR_APPS) -iname "*.erl" -or -iname "*.hrl" -or -iname "*.app.src")
RTGW_CONFIG := $(RTGW_DIR_ROOT)/rebar.config $(RTGW_DIR_CONFIG)/sys.config $(RTGW_DIR_CONFIG)/vm.args

.PHONY: all
all: $(RTGW_CONFIG) $(RELEASE_BIN) $(RELEASE_BIN_CLI)

################################################################################
# Build

REBAR := $(abspath ./)/rebar3

ROUTER_PROTOS_GENERATED_SOURCE := $(shell find $(ROUTER_DIR_APPS)/router_pb -type f -iname "*_definitions.erl")
ROUTER_PROTOS_GENERATED_HEADERS := $(shell find $(ROUTER_DIR_APPS)/router_pb -type f -iname "*_definitions.hrl")
$(RELEASE_BIN): $(RTGW_SOURCE) $(RTGW_CONFIG) $(ROUTER_PROTOS_GENERATED_SOURCE) $(ROUTER_PROTOS_GENERATED_HEADERS)
	@mkdir -p $(RTGW_DIR_ROOT)/apps/rtgw/src/generated
	@mkdir -p $(RTGW_DIR_ROOT)/apps/rtgw/include
	@for file in $(ROUTER_PROTOS_GENERATED_SOURCE); do \
		echo "Copying $$file"; \
		cp $$file $(RTGW_DIR_ROOT)/apps/rtgw/src/generated/.; \
	done
	@for file in $(ROUTER_PROTOS_GENERATED_HEADERS); do \
		echo "Copying $$file"; \
		cp $$file $(RTGW_DIR_ROOT)/apps/rtgw/include/.; \
	done
	$(REBAR) release

################################################################################
# Run

.PHONY: shell
shell: compile
	$(REBAR) shell

.PHONY: run
run: $(RELEASE_BIN)
	$(call print_app_env)
	$(RELEASE_BIN) console

.PHONY: logtail
RTGW_LOGTAIL_LEVEL ?= debug
logtail:
	tail -F $(RTGW_DIR_LOGS)/$(RTGW_VMARGS_SNAME)_$(RTGW_LOGTAIL_LEVEL).log.1 | grcat $(ROUTER_DIR_ROOT)/.grc-flatlog.conf

################################################################################
# Test

.PHONY: check
check: all

################################################################################
# Clean

.PHONY: clean
clean:
	$(REBAR) clean -a
	rm $(RTGW_DIR_ROOT)/apps/rtgw_grpc/src/generated/*_definitions.erl
	rm $(RTGW_DIR_ROOT)/apps/rtgw_grpc/include/*_definitions.hrl

.PHONY: dist-clean
dist-clean:
	$(REBAR) unlock --all
	rm -rf _build
