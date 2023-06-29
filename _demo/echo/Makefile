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

ECHO_DIR_ROOT := $(abspath ./)
ECHO_DIR_APPS := $(ECHO_DIR_ROOT)/apps
ECHO_DIR_CONFIG := $(ECHO_DIR_ROOT)/config
ECHO_DIR_BUILD := $(ECHO_DIR_ROOT)/_build
ECHO_DIR_LOGS := $(ECHO_DIR_ROOT)/_logs

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
	@printenv | grep ^ECHO | grep -v print_app_env
endef

include env-vars.mk

################################################################################
# Default target

RELEASE_BIN := $(ECHO_DIR_BUILD)/default/rel/echo/bin/echo

ECHO_SOURCE := $(shell find $(ECHO_DIR_APPS) -iname "*.erl" -or -iname "*.hrl" -or -iname "*.app.src")
ECHO_CONFIG := $(ECHO_DIR_ROOT)/rebar.config $(ECHO_DIR_CONFIG)/sys.config $(ECHO_DIR_CONFIG)/vm.args

.PHONY: all
all: $(ECHO_CONFIG) $(RELEASE_BIN) $(RELEASE_BIN_CLI)

################################################################################
# Build

REBAR := $(abspath ./)/rebar3

ROUTER_PROTOS_GENERATED_SOURCE := $(shell find $(ROUTER_DIR_APPS)/router_pb -type f -iname "*_definitions.erl")
ROUTER_PROTOS_GENERATED_HEADERS := $(shell find $(ROUTER_DIR_APPS)/router_pb -type f -iname "*_definitions.hrl")
$(RELEASE_BIN): $(ECHO_SOURCE) $(ECHO_CONFIG) $(ROUTER_PROTOS_GENERATED_SOURCE) $(ROUTER_PROTOS_GENERATED_HEADERS)
	@mkdir -p $(ECHO_DIR_ROOT)/apps/echo/src/generated
	@mkdir -p $(ECHO_DIR_ROOT)/apps/echo/include
	@for file in $(ROUTER_PROTOS_GENERATED_SOURCE); do \
		echo "Copying $$file"; \
		cp $$file $(ECHO_DIR_ROOT)/apps/echo/src/generated/.; \
	done
	@for file in $(ROUTER_PROTOS_GENERATED_HEADERS); do \
		echo "Copying $$file"; \
		cp $$file $(ECHO_DIR_ROOT)/apps/echo/include/.; \
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
ECHO_LOGTAIL_LEVEL ?= debug
logtail:
	tail -F $(ECHO_DIR_LOGS)/$(ECHO_VMARGS_SNAME)_$(ECHO_LOGTAIL_LEVEL).log.1 | grcat $(ROUTER_DIR_ROOT)/.grc-flatlog.conf

################################################################################
# Test

.PHONY: check
check: all

################################################################################
# Clean

.PHONY: clean
clean:
	$(REBAR) clean -a
	rm $(ECHO_DIR_ROOT)/apps/echo_grpc/src/generated/*_definitions.erl
	rm $(ECHO_DIR_ROOT)/apps/echo_grpc/include/*_definitions.hrl

.PHONY: dist-clean
dist-clean:
	$(REBAR) unlock --all
	rm -rf _build
