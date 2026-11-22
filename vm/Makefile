# Samaltak VM. `make` → build/samaltak. NO_PLATFORM=1 builds a headless-only VM.
# The sources are gen/: C translated from the Lowtalk modules in src/VM-Core and src/VM-Platform (make translate at
# the top level regenerates them); gen/sources.mk says which files make the core and which the platform layer, and
# which of them are for one OS only (VM_CORE_SOURCES_LINUX ...: this build adds those of its uname -s) or for one CPU
# (VM_CORE_SOURCES_X86_64: this build adds those of its uname -m, arm64's on any CPU but x86-64).
# macOS: Homebrew sdl3 and openssl@3, clang. Linux: sdl3, shaderc (GLSL → SPIR-V for SDL_GPU on Vulkan) and OpenSSL 3, gcc
# or clang.
# Profile-guided: pgo.profdata (if present) steers optimization; `make pgo IMAGE=...` retrains it. NO_PGO=1 skips it.
# C4_PLATFORM_FILES=1 builds an interpreter-only C4 VM with audited platform file primitives (Linux x86-64).
# C4_PLATFORM_SDL=1 adds audited SDL windows, input and CPU presentation (Linux x86-64).
# BRIEF=1 prints one line per file instead of the commands.
VM_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
UNAME_S := $(shell uname -s)
OS := $(shell echo $(UNAME_S) | tr a-z A-Z)
ARCH := $(if $(filter x86_64 amd64,$(shell uname -m)),X86_64,ARM64)
CC ?= cc
IS_CLANG := $(shell $(CC) --version 2>/dev/null | grep -q clang && echo yes)
ifeq ($(IS_CLANG),yes)
  CFLAGS ?= -O2 -g -flto
else
  # gcc: -flto=auto spreads the link over the cores. Its extra warnings about generated code are not bugs: comparisons
  # always true for some types, && inside ||, uninitialized locals on paths the code never takes, and messages cut to
  # the error buffer's size on purpose.
  CFLAGS ?= -O2 -g -flto=auto
  CFLAGS += -Wno-type-limits -Wno-parentheses -Wno-maybe-uninitialized -Wno-format-truncation
endif
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -MMD -MP -Igen -I"$(VM_DIR)"
ifeq ($(UNAME_S),Darwin)
  CFLAGS += -D_DARWIN_C_SOURCE
  OS_PLATFORM_LIBS := -framework CoreVideo -lobjc
else
  # The VM was written for Darwin's arm64 ABI, where char is signed; Linux's makes it unsigned.
  CFLAGS += -D_GNU_SOURCE -fsigned-char
  OS_PLATFORM_LIBS := $(shell pkg-config --libs shaderc 2>/dev/null || echo -lshaderc_shared)
endif
LDLIBS += -lm -lpthread

ifeq ($(C4_PLATFORM_SDL),1)
  BUILD := build/c4-sdl
  ifeq ($(abspath $(BUILD)),$(abspath build))
    $(error C4_PLATFORM_SDL=1 cannot use the default build directory)
  endif
else
  BUILD := build
endif
PGO_PROFILE := pgo.profdata
LLVM_PROFDATA := $(shell xcrun -f llvm-profdata 2>/dev/null || command -v llvm-profdata)
ifneq ($(IS_CLANG),yes)
  # The profile is clang's (llvm-profdata); gcc builds without it.
  NO_PGO := 1
endif
ifneq ($(PGO_GEN),)
  CFLAGS += -fprofile-instr-generate=$(CURDIR)/$(BUILD)/prof/%p.profraw
  LDFLAGS += -fprofile-instr-generate
else ifeq ($(and $(wildcard $(PGO_PROFILE)),$(if $(NO_PGO),,yes)),yes)
  CFLAGS += -fprofile-instr-use=$(PGO_PROFILE) -Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled
  PGO_DEP := $(PGO_PROFILE)
endif
include gen/sources.mk
CORE_SRCS := $(addprefix gen/,$(VM_CORE_SOURCES) $(VM_CORE_SOURCES_$(OS)) $(VM_CORE_SOURCES_$(ARCH)))
HEADLESS_SRCS := $(addprefix gen/,$(VM_HEADLESS_SOURCES) $(VM_HEADLESS_SOURCES_$(OS)) $(VM_HEADLESS_SOURCES_$(ARCH)))
PLATFORM_SRCS := $(addprefix gen/,$(VM_PLATFORM_SOURCES) $(VM_PLATFORM_SOURCES_$(OS)) $(VM_PLATFORM_SOURCES_$(ARCH)))

SDL_CFLAGS := $(shell pkg-config --cflags sdl3 2>/dev/null)
SDL_LIBS := $(shell pkg-config --libs sdl3 2>/dev/null)
ifeq ($(SDL_LIBS),)
  ifneq ($(wildcard /opt/homebrew/include/SDL3/SDL.h),)
    SDL_CFLAGS := -I/opt/homebrew/include
    SDL_LIBS := -L/opt/homebrew/lib -Wl,-rpath,/opt/homebrew/lib -lSDL3
  endif
endif

# OpenSSL 3 (TLS): pkg-config, else Homebrew's keg-only openssl@3.
SSL_CFLAGS := $(shell pkg-config --cflags openssl 2>/dev/null)
SSL_LIBS := $(shell pkg-config --libs openssl 2>/dev/null)
ifeq ($(SSL_LIBS),)
  SSL_PREFIX := $(shell brew --prefix openssl@3 2>/dev/null)
  SSL_CFLAGS := $(if $(SSL_PREFIX),-I$(SSL_PREFIX)/include)
  SSL_LIBS := $(if $(SSL_PREFIX),-L$(SSL_PREFIX)/lib) -lssl -lcrypto
endif

ifneq ($(and $(PLATFORM_SRCS),$(SDL_LIBS),$(if $(NO_PLATFORM),,yes)),)
  VARIANT := platform
  SRCS := $(CORE_SRCS) $(PLATFORM_SRCS)
  CFLAGS += $(SDL_CFLAGS) $(SSL_CFLAGS)
  LDLIBS += $(SDL_LIBS) $(SSL_LIBS) $(OS_PLATFORM_LIBS)
  ifeq ($(C4_PLATFORM_SDL),1)
    VARIANT := c4-platform-sdl
    CFLAGS += -DSAMALTAK_C4_PLATFORM_SDL
  else ifeq ($(C4_PLATFORM_FILES),1)
    VARIANT := c4-platform-files
    CFLAGS += -DSAMALTAK_C4_PLATFORM_FILES
  endif
else
  VARIANT := headless
  SRCS := $(CORE_SRCS) $(HEADLESS_SRCS)
  CFLAGS += -DSAMALTAK_NO_PLATFORM
endif

ifeq ($(C4_PLATFORM_FILES),1)
  ifneq ($(OS)/$(ARCH)/$(VARIANT),LINUX/X86_64/c4-platform-files)
    $(error C4_PLATFORM_FILES=1 requires Linux x86-64 and the platform build dependencies)
  endif
endif
ifeq ($(C4_PLATFORM_SDL),1)
  ifneq ($(OS)/$(ARCH)/$(VARIANT),LINUX/X86_64/c4-platform-sdl)
    $(error C4_PLATFORM_SDL=1 requires Linux x86-64 and the platform build dependencies)
  endif
endif
ifeq ($(OS)/$(ARCH),LINUX/X86_64)
  ifneq ($(filter headless c4-platform-files c4-platform-sdl,$(VARIANT)),)
    SRCS += c4_heap.c
    vpath c4_heap.c $(VM_DIR)
  endif
endif

OBJDIR := $(BUILD)/obj-$(VARIANT)
OBJS := $(patsubst %.c,$(OBJDIR)/%.o,$(SRCS))
STAMP := $(BUILD)/.variant-$(VARIANT)

$(BUILD)/samaltak: $(OBJS) $(EXTRA_OBJS) $(STAMP)
	$(if $(BRIEF),@echo "link $@";) $(CC) $(CFLAGS) -o $@ $(OBJS) $(EXTRA_OBJS) $(LDFLAGS) $(LDLIBS)

$(STAMP):
	@mkdir -p $(BUILD)
	@rm -f $(BUILD)/.variant-* $(BUILD)/samaltak
	@touch $@

$(OBJDIR)/%.o: %.c $(PGO_DEP)
	@mkdir -p $(dir $@)
	$(if $(BRIEF),@echo "cc   $<";) $(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

# Retrain the profile: an instrumented VM runs the benchmarks (also under the baseline JIT) and the kernel/compiler tests on IMAGE.
pgo:
	@test -n "$(IMAGE)" || { echo "usage: make pgo IMAGE=path/to/samaltak.image"; exit 1; }
	rm -rf build/pgo-gen/prof
	$(MAKE) BUILD=build/pgo-gen PGO_GEN=1
	build/pgo-gen/samaltak $(IMAGE) --headless --eval "$$(cat tests/bench/suite-samaltak.st)" > /dev/null
	build/pgo-gen/samaltak $(IMAGE) --headless --eval "$$(cat tests/bench/bench.st)" > /dev/null
	build/pgo-gen/samaltak --jit baseline $(IMAGE) --headless --eval "$$(cat tests/bench/suite-samaltak.st)" > /dev/null
	build/pgo-gen/samaltak $(IMAGE) --headless --test KernelTestProxy CollectionTest StringTest IntegerTest CompilerTest > /dev/null
	$(LLVM_PROFDATA) merge -o $(PGO_PROFILE) build/pgo-gen/prof/*.profraw

clean:
	rm -rf $(BUILD)/samaltak $(BUILD)/obj-* $(BUILD)/.variant-*

.PHONY: clean pgo
-include $(OBJS:.o=.d)
