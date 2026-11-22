# Tests of the platform layer (src/VM-Platform, translated into ../gen): gpu_test links the generated platform
# internals without the VM; st-test runs Smalltalk through the real VM.
SDL_CFLAGS ?= $(shell pkg-config --cflags sdl3 2>/dev/null || echo -I/opt/homebrew/include)
SDL_LIBS ?= $(shell pkg-config --libs sdl3 2>/dev/null || echo -L/opt/homebrew/lib -lSDL3)
CFLAGS ?= -std=gnu11 -O2 -g -Wall -Wextra -Wno-unused-parameter
UNAME_S := $(shell uname -s)
OS := $(shell echo $(UNAME_S) | tr a-z A-Z)
ifeq ($(UNAME_S),Darwin)
  OS_CFLAGS := -D_DARWIN_C_SOURCE
  OS_LIBS := -framework CoreVideo -lobjc
else
  # gcc's extra warnings about the generated code are not bugs (see ../Makefile)
  OS_CFLAGS := -D_GNU_SOURCE -fsigned-char -Wno-type-limits -Wno-parentheses -Wno-maybe-uninitialized -Wno-format-truncation
  OS_LIBS := $(shell pkg-config --libs shaderc 2>/dev/null || echo -lshaderc_shared)
endif
# OpenSSL 3, as in ../Makefile
SSL_CFLAGS := $(shell pkg-config --cflags openssl 2>/dev/null)
SSL_LIBS := $(shell pkg-config --libs openssl 2>/dev/null)
ifeq ($(SSL_LIBS),)
  SSL_PREFIX := $(shell brew --prefix openssl@3 2>/dev/null)
  SSL_CFLAGS := $(if $(SSL_PREFIX),-I$(SSL_PREFIX)/include)
  SSL_LIBS := $(if $(SSL_PREFIX),-L$(SSL_PREFIX)/lib) -lssl -lcrypto
endif
BUILD := ../build/platform-test
GEN := ../gen
include $(GEN)/sources.mk
INTERNALS := $(addprefix $(GEN)/,$(filter-out platform_primitives.c,$(VM_PLATFORM_SOURCES) $(VM_PLATFORM_SOURCES_$(OS))))

test: $(BUILD)/gpu_test
	$(BUILD)/gpu_test

$(BUILD)/gpu_test: tests/gpu_test.c $(INTERNALS) $(GEN)/samaltak.h ../c4_heap.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(OS_CFLAGS) -I$(GEN) -I.. $(SDL_CFLAGS) $(SSL_CFLAGS) -o $@ tests/gpu_test.c $(INTERNALS) $(SDL_LIBS) $(SSL_LIBS) $(OS_LIBS) -lpthread

# Through the real VM (built into its own directory so it never clobbers vm/build/samaltak).
st-test:
	$(MAKE) -C .. BUILD=build/platform-vm
	tests/st_test.sh $(CURDIR)/../build/platform-vm/samaltak

clean:
	rm -rf $(BUILD)

.PHONY: test st-test clean
