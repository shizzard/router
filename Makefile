################################################################################
# Prepare

.EXPORT_ALL_VARIABLES:
.ONESHELL:
.DELETE_ON_ERROR:
.SHELLFLAGS := -eu -o pipefail -c
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
SHELL := bash

ERLC := $(shell which erlc)
DOCKER := $(shell which docker)
PYTHON3 := $(shell which python3)
PIP3 := $(shell which pip3)

ROUTER_DIR_ROOT := $(abspath ./)
ROUTER_DIR_APPS := $(ROUTER_DIR_ROOT)/apps
ROUTER_DIR_CONFIG := $(ROUTER_DIR_ROOT)/config
ROUTER_DIR_TESTS := $(ROUTER_DIR_ROOT)/test
ROUTER_DIR_PLT := $(ROUTER_DIR_ROOT)/.plt
ROUTER_DIR_BUILD := $(ROUTER_DIR_ROOT)/_build
ROUTER_DIR_TOOLS := $(ROUTER_DIR_ROOT)/_tools
ROUTER_DIR_LOGS := $(ROUTER_DIR_ROOT)/_logs
ROUTER_DIR_PROTO := $(ROUTER_DIR_APPS)/router_pb/priv/proto

ifeq (, $(ERLC))
$(warning "No erlc found, is erlang installed?")
endif
ifeq (, $(DOCKER))
$(warning "No docker found, is it installed?")
endif

REQUIRED_DIRS = $(ROUTER_DIR_TOOLS) $(ROUTER_DIR_LOGS)
_MKDIRS := $(shell for d in $(REQUIRED_DIRS); do \
		[[ -d $$d ]] || mkdir -p $$d; \
	done)

define print_app_env
	@printenv | grep ^ROUTER | grep -v print_app_env
endef

include env-vars.mk

################################################################################
# Default target

RELEASE_BIN := $(ROUTER_DIR_BUILD)/default/rel/router/bin/router
RELEASE_BIN_CLI := $(ROUTER_DIR_BUILD)/default/bin/router

RELEASE_TEST_BIN := $(ROUTER_DIR_BUILD)/test/rel/router/bin/router
RELEASE_TEST_BIN_CLI := $(ROUTER_DIR_BUILD)/test/bin/router

RELEASE_PROD_BIN := $(ROUTER_DIR_BUILD)/prod/rel/router/bin/router
RELEASE_PROD_BIN_CLI := $(ROUTER_DIR_BUILD)/prod/bin/router

SOURCE := $(shell find apps -iname "*.erl" -or -iname "*.hrl" -or -iname "*.app.src")
PROTO := $(shell find apps -iname "*.proto")
CONFIG := $(ROUTER_DIR_ROOT)/rebar.config $(ROUTER_DIR_CONFIG)/sys.config $(ROUTER_DIR_CONFIG)/vm.args

.PHONY: all
all: $(CONFIG) $(RELEASE_BIN) $(RELEASE_BIN_CLI)

################################################################################
# Tools

ROUTER_DIR_TOOLS_LUX := $(ROUTER_DIR_TOOLS)/lux
TOOL_LUX := $(ROUTER_DIR_TOOLS_LUX)/bin/lux
$(TOOL_LUX):
	git clone https://github.com/hawk/lux.git $(ROUTER_DIR_TOOLS_LUX)
	@cd $(ROUTER_DIR_TOOLS_LUX) && autoconf && ./configure && make

################################################################################
# Helpers

.PHONY: version
version:
	@echo $(shell git describe --tags)

################################################################################
# Erlang build

REBAR := $(abspath ./)/rebar3

$(RELEASE_BIN): $(SOURCE) $(PROTO) $(CONFIG)
	$(REBAR) release

$(RELEASE_BIN_CLI): $(SOURCE) $(PROTO) $(CONFIG)
	$(REBAR) escriptize

$(RELEASE_TEST_BIN): $(SOURCE) $(PROTO) $(CONFIG)
	$(REBAR) as test release

$(RELEASE_TEST_BIN_CLI): $(SOURCE) $(PROTO) $(CONFIG)
	$(REBAR) as test escriptize

$(RELEASE_PROD_BIN):
	$(REBAR) as prod release

$(RELEASE_PROD_BIN_CLI):
	$(REBAR) as prod escriptize

# latter targets are for production builds

.PHONY: release-prod
release-prod: $(RELEASE_PROD_BIN) $(RELEASE_PROD_BIN_CLI)

.PHONY: dockerize
dockerize:
	$(DOCKER) build --tag 'router:$(shell git describe --tags)' $(ROUTER_DIR_ROOT)

################################################################################
# Erlang run

.PHONY: shell
shell: compile
	$(REBAR) shell

.PHONY: run
run: $(RELEASE_BIN)
	$(call print_app_env)
	$(RELEASE_BIN) console

################################################################################
# Erlang test

.PHONY: check
check: dialyze unit-tests common-tests lux-tests

.PHONY: dialyze
dialyze:
	@echo ":: DIALYZER RUN"
	$(REBAR) as test dialyzer
	@echo ":: DIALYZER END"

.PHONY: unit-tests
unit-tests:
	@echo ":: EUNIT RUN"
	$(REBAR) as test eunit
	@echo "::   EUNIT END"

.PHONY: common-tests
ROUTER_DIR_TESTS_CT := $(ROUTER_DIR_TESTS)/ct
common-tests:
	@echo ":: CT RUN"
	$(call print_app_env)
	$(REBAR) as test ct -v -c --verbosity 100 --logdir $(ROUTER_DIR_TESTS_CT)/_logs
	@echo ":: CT END"

.PHONY: lux-tests
ROUTER_DIR_TESTS_LUX := $(ROUTER_DIR_TESTS)/lux
lux-tests: $(RELEASE_TEST_BIN) $(RELEASE_TEST_BIN_CLI) $(TOOL_LUX)
	@echo ":: LUX RUN"
ifeq (,$(TEST))
	@$(foreach dir,\
		$(shell $(TOOL_LUX) --mode=list_dir $(ROUTER_DIR_TESTS_LUX)),\
		echo; echo " -> TESTCASE $(dir)"; $(MAKE) -C $(dir) build all; echo;)
else
	@echo; \
		echo " -> TESTCASE $(shell dirname $(TEST))"; \
		$(MAKE) -C $(shell dirname $(TEST)) build $(shell basename $(TEST) | cut -f 1 -d '.').test; \
		echo;
endif
	@echo ":: LUX END"

.PHONY: lux-clean
ROUTER_DIR_TESTS_LUX := $(ROUTER_DIR_TESTS)/lux
lux-clean: $(RELEASE_TEST_BIN) $(RELEASE_TEST_BIN_CLI) $(TOOL_LUX)
	@echo ":: LUX CLEAN"
	@$(foreach dir,\
		$(shell $(TOOL_LUX) --mode=list_dir $(ROUTER_DIR_TESTS_LUX)),\
		echo; echo " -> TESTCASE $(dir)"; $(MAKE) -C $(dir) clean; echo;)
	@echo ":: LUX END"

################################################################################
# Erlang clean

.PHONY: clean
clean: lux-clean
	$(REBAR) clean -a

.PHONY: dist-clean
dist-clean: clean
	$(REBAR) unlock
	rm -rf _build
