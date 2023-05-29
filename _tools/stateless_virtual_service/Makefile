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

SV_SERVICE_DIR_ROOT := $(abspath ./)

SV_SERVICE_EXEC := $(SV_SERVICE_DIR_ROOT)/service.py
PROTOC_EXEC := $(VENV_PYTHON3) -m grpc_tools.protoc

VENV_NAME ?= venv
VENV_PYTHON3 := ${VENV_NAME}/bin/python3
VENV_ACTIVATE = . $(VENV_NAME)/bin/activate

include env-vars.mk

################################################################################
# Build

PROTOS := $(wildcard $(SV_SERVICE_DIR_ROOT)/*.proto)
PROTOS_OUT := $(foreach proto, $(PROTOS), $(subst .proto,_pb2_grpc.py, $(proto)))
build: $(VENV_NAME)/bin/activate $(PROTOS_OUT)

%_pb2_grpc.py: %.proto
	$(PROTOC_EXEC) -I$(SV_SERVICE_DIR_ROOT) --python_out=. --grpc_python_out=. $*.proto

$(VENV_NAME)/bin/activate: requirements.txt
	test -d $(VENV_NAME) || python3 -m venv $(VENV_NAME)
	${VENV_PYTHON3} -m pip install -U pip
	${VENV_PYTHON3} -m pip install -Ur requirements.txt
	touch $(VENV_NAME)/bin/activate

################################################################################
# Run

run: build
	$(VENV_ACTIVATE) && $(VENV_PYTHON3) $(SV_SERVICE_EXEC) --port $(SV_SERVICE_PORT)

################################################################################
# Clean

clean:
	rm -rf $(VENV_NAME)
	find . -name '*.pyc' -delete
	find . -name '__pycache__' -type d -delete
	find . -name '*_pb2.py' -delete
	find . -name '*_pb2_grpc.py' -delete
