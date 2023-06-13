################################################################################
# Prepare

.EXPORT_ALL_VARIABLES:
.ONESHELL:
.DELETE_ON_ERROR:
.SHELLFLAGS := -eu -o pipefail -c
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
SHELL := bash

include arch.mk

################################################################################
# Directories

ROUTER_DIR_ROOT := $(abspath ./)
ROUTER_DIR_APPS := $(ROUTER_DIR_ROOT)/apps
ROUTER_DIR_CONFIG := $(ROUTER_DIR_ROOT)/config
ROUTER_DIR_TESTS := $(ROUTER_DIR_ROOT)/test
ROUTER_DIR_PLT := $(ROUTER_DIR_ROOT)/.plt
ROUTER_DIR_BUILD := $(ROUTER_DIR_ROOT)/_build
ROUTER_DIR_TOOLS := $(ROUTER_DIR_ROOT)/_tools
ROUTER_DIR_LOGS := $(ROUTER_DIR_ROOT)/_logs
ROUTER_DIR_PROTO := $(ROUTER_DIR_APPS)/router_pb/priv/proto

REQUIRED_DIRS = $(ROUTER_DIR_TOOLS) $(ROUTER_DIR_LOGS)
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
TOOL_LUX_VERSION := $(shell cat $(ROUTER_DIR_TOOLS)/.lux_version)
$(TOOL_LUX):
	mkdir -p $(ROUTER_DIR_TOOLS_LUX)
	git clone --branch $(TOOL_LUX_VERSION) --depth 1 https://github.com/hawk/lux.git $(ROUTER_DIR_TOOLS_LUX)
	@cd $(ROUTER_DIR_TOOLS_LUX) && autoconf && ./configure && make

ROUTER_DIR_TOOLS_EVANS := $(ROUTER_DIR_TOOLS)/evans
TOOL_EVANS := $(ROUTER_DIR_TOOLS_EVANS)/evans
TOOL_EVANS_VERSION := $(shell cat $(ROUTER_DIR_TOOLS)/.evans_version)
$(TOOL_EVANS):
	mkdir -p $(ROUTER_DIR_TOOLS_EVANS)
	curl -L -o $(ROUTER_DIR_TOOLS_EVANS)/evans.tar.gz \
	https://github.com/ktr0731/evans/releases/download/$(TOOL_EVANS_VERSION)/evans_$(OS)_$(ARCH).tar.gz
	tar -xvf $(ROUTER_DIR_TOOLS_EVANS)/evans.tar.gz -C $(ROUTER_DIR_TOOLS_EVANS)

ROUTER_DIR_TOOLS_STATELESS_SERVICE := $(ROUTER_DIR_TOOLS)/stateless_virtual_service
TOOL_STATELESS_SERVICE := $(ROUTER_DIR_TOOLS_STATELESS_SERVICE)/service.py
stateless-service-%:
	$(MAKE) -C $(ROUTER_DIR_TOOLS_STATELESS_SERVICE) $*

################################################################################
# Helpers

.PHONY: version
version:
	@echo $(shell git describe --tags)

################################################################################
# Build

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
# Run

.PHONY: shell
shell: compile
	$(REBAR) shell

.PHONY: run
run: $(RELEASE_BIN)
	$(call print_app_env)
	$(RELEASE_BIN) console

.PHONY: logtail
ROUTER_LOGTAIL_LEVEL ?= debug
logtail:
	tail -F $(ROUTER_DIR_LOGS)/lgr_$(ROUTER_LOGTAIL_LEVEL).log.1 | grcat .grc-flatlog.conf

################################################################################
# Test

.PHONY: check
# Adding `all` as a dependency to check if the release is assembling correctly
check: all dialyze unit-tests common-tests lux-tests

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
ROUTER_DIR_TESTS_CT_LOGS := $(ROUTER_DIR_TESTS_CT)/_logs
COMMON_TEST_OPTS ?=
common-tests:
	@echo ":: CT RUN"
	$(REBAR) as test ct --logdir $(ROUTER_DIR_TESTS_CT_LOGS) $(COMMON_TEST_OPTS)
	@echo ":: CT END"

.PHONY: lux-tests
ROUTER_DIR_TESTS_LUX := $(ROUTER_DIR_TESTS)/lux
TEST_CASES := $(shell \
	find $(ROUTER_DIR_TESTS_LUX) -type f -iname "*.lux" -exec dirname {} \; \
  | grep '$(SCOPE)' | sort -u \
)
FAILED_CASES := $(ROUTER_DIR_TESTS_LUX)/.failed_cases
lux-tests: $(RELEASE_TEST_BIN) $(RELEASE_TEST_BIN_CLI) $(TOOL_LUX) $(TOOL_EVANS)
	@echo ":: LUX TESTS"
	rm -f $(FAILED_CASES)
	@$(foreach TEST_CASE, $(TEST_CASES), \
		echo; echo; \
		echo "     -> TEST CASE $(TEST_CASE)"; \
		$(MAKE) -C $(TEST_CASE) build all || \
		echo "$(TEST_CASE) (file://`realpath $(TEST_CASE)`/lux_logs/latest_run/lux_summary.log.html)" >> $(FAILED_CASES); \
	)
	@echo; echo
	@echo "$(strip $(shell echo $(TEST_CASES) | tr ' ' '\n' | wc -l)) test cases executed."
	@if [ -e "$(FAILED_CASES)" ]; then \
		echo "`cat $(FAILED_CASES) | wc -l | xargs` failed cases:"; \
		cat $(FAILED_CASES); \
		rm $(FAILED_CASES); \
		echo ":: LUX END"; \
		exit 1; \
	else \
		echo "All test cases passed."; \
		echo ":: LUX END"; \
	fi

# quite dirty, but useful for debugging tests
.PHONY: lux-logtail
TEST_CASES_LOGFILES := $(foreach TEST_CASE, $(TEST_CASES), $(addsuffix /router_logs/test/lgr_debug.log.1, $(TEST_CASE)))
lux-logtail:
	tail -F $(TEST_CASES_LOGFILES) | grcat .grc-flatlog.conf

################################################################################
# Clean

.PHONY: common-clean
common-clean:
	rm -rf $(ROUTER_DIR_TESTS_CT_LOGS)

.PHONY: lux-clean
lux-clean:
	@echo ":: LUX CLEAN"
	@$(foreach TEST_CASE, $(TEST_CASES), \
		echo; echo; \
		echo "     -> TEST CASE $(TEST_CASE)"; \
		$(MAKE) -C $(TEST_CASE) clean; \
	)
	@echo
	@echo ":: LUX END";

.PHONY: clean
clean: common-clean lux-clean
	$(REBAR) clean -a

.PHONY: dist-clean
dist-clean: clean
	$(REBAR) unlock --all
	rm -rf _build
	rm -rf $(ROUTER_DIR_TOOLS_LUX) $(ROUTER_DIR_TOOLS_EVANS)
