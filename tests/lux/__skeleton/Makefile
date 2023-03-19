export TEST_ROOT := $(abspath ./)
include ./*.mk

JQ := $(shell which jq)

ifeq (, $(JQ))
$(warning "No jq found, is it installed?")
endif

.PHONY: all
all:
	@$(TOOL_LUX) --doc 1 .
	$(TOOL_LUX) --html enable .

.PHONY: build
build:

.PHONY: clean
clean:
	rm -rf lux_logs
