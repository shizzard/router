UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
OS := linux
else ifeq ($(UNAME_S),Darwin)
OS := darwin
else
$(warning "Cannot determine the OS (`uname -s` returned '$(UNAME_S)'. Are you running MS Windows?!)")
OS := undefined
endif

UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),x86_64)
ARCH := amd64
endif
ifneq ($(filter %86,$(UNAME_M)),)
ARCH := 386
endif
ifeq ($(UNAME_M),arm64)
ARCH := arm64
endif
ifeq ($(UNAME_M),arm)
ARCH := arm
endif
