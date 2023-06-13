################################################################################
# Prepare

.EXPORT_ALL_VARIABLES:
.ONESHELL:
.DELETE_ON_ERROR:
.SHELLFLAGS := -eu -o pipefail -c
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
SHELL := bash

PYTHON3 := $(shell which python3)

ifeq (, $(PYTHON3))
$(warning "No python3 found, is it installed?")
endif

STATELESS_SERVICE_DIR_ROOT := $(abspath ./)

VENV_NAME ?= venv
VENV_PYTHON3 := ${VENV_NAME}/bin/python3
VENV_ACTIVATE = . $(VENV_NAME)/bin/activate

STATELESS_SERVICE_EXEC := $(STATELESS_SERVICE_DIR_ROOT)/service.py
PROTOC_EXEC := $(VENV_PYTHON3) -m grpc_tools.protoc

include env-vars.mk

################################################################################
# Build

PROTOS := $(wildcard $(STATELESS_SERVICE_DIR_ROOT)/*.proto)
PROTOS_OUT := $(foreach proto, $(PROTOS), $(subst .proto,_pb2_grpc.py, $(proto)))
build: $(VENV_NAME)/bin/activate $(PROTOS_OUT)

%_pb2_grpc.py: %.proto
	$(PROTOC_EXEC) -I$(STATELESS_SERVICE_DIR_ROOT) --python_out=. --grpc_python_out=. $*.proto

$(VENV_NAME)/bin/activate: requirements.txt
	test -d $(VENV_NAME) || $(PYTHON3) -m venv $(VENV_NAME)
	${VENV_PYTHON3} -m pip install -U pip
	${VENV_PYTHON3} -m pip install -Ur requirements.txt
	touch $(VENV_NAME)/bin/activate

################################################################################
# Run

run: build
	$(VENV_ACTIVATE) && $(VENV_PYTHON3) $(STATELESS_SERVICE_EXEC) --port $(STATELESS_SERVICE_PORT)

################################################################################
# Clean

clean:
	rm -rf $(VENV_NAME)
	find . -name '*.pyc' -delete
	find . -name '__pycache__' -type d -delete
	find . -name '*_pb2.py' -delete
	find . -name '*_pb2_grpc.py' -delete
