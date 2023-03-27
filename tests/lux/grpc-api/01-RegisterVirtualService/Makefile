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
EVANS := $(shell which evans)

ifeq (, $(JQ))
$(warning "No jq found, is it installed?")
endif

ifeq (, $(EVANS))
$(warning "No evans found, is it installed? See https://github.com/ktr0731/evans")
endif

.PHONY: all
all:
	@$(TOOL_LUX) --doc 1 .
	$(TOOL_LUX) --html enable .

.PHONY: build
build:

.PHONY: clean
clean:
	rm -rf lux_logs router_logs
