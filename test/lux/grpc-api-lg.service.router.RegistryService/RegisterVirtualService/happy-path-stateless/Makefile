################################################################################
# Prepare

.EXPORT_ALL_VARIABLES:
.ONESHELL:
.DELETE_ON_ERROR:
.SHELLFLAGS := -eu -o pipefail -c
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
SHELL := bash

export TEST_ROOT := $(abspath ./)
-include ./*.mk

JQ := $(shell which jq)

ifeq (, $(JQ))
$(warning "No jq found, is it installed?")
endif

.PHONY: all
all: clean-json
	@mkdir -p lux_logs
	@printenv | grep ^ROUTER | grep -v print_app_env > lux_logs/latest_run.log
	@$(TOOL_LUX) --progress doc --html enable . | tee -a lux_logs/latest_run.log; exit $${PIPESTATUS[0]}

.PHONY: build
build:

.PHONY: clean
clean: clean-json clean-router-logs
	rm -rf lux_logs

.PHONY: clean-router-logs
clean-router-logs:
	rm -rf router_logs

.PHONY: clean-json
TMP_RESPONSE_FILES := $(shell find . -type f -iname "*.response.json")
TMP_REQUEST_FILES := $(shell find . -iname "*.template.json" -type f -exec bash -c 'f="$${1%.template.json}.json"; [ -e "$$f" ] && echo "$$f"' _ {} \;)
clean-json:
ifneq (,$(TMP_REQUEST_FILES))
	rm -rf $(TMP_REQUEST_FILES)
endif
ifneq (,$(TMP_RESPONSE_FILES))
	rm -rf $(TMP_RESPONSE_FILES)
endif
