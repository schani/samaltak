# The VM as a UEFI application (make uefi at the top): the C of GEN (VMTranslator generateVMInto:os:arch: with #uefi,
# docs/uefi.md) compiled freestanding for UEFI_TARGET (x86_64 or aarch64) with the ABI the JIT assumes (on x86-64 System V;
# calls into the firmware are ms_abi), linked into a static PIE that UefiImageWriter turns into PE32+. No C library:
# VM-UEFI's modules take its place.
GEN ?= gen-uefi
OBJ ?= build/uefi
UEFI_CC ?= clang
UEFI_LD ?= ld.lld
UEFI_TARGET ?= x86_64
UEFI_CFLAGS := -target $(UEFI_TARGET)-unknown-none-elf -ffreestanding -fno-builtin -fno-stack-protector -fPIE -mno-red-zone \
	-fno-math-errno -ffp-contract=off -O2 -std=gnu11 -fsigned-char -DSAMALTAK_UEFI -I$(GEN) -I$(dir $(lastword $(MAKEFILE_LIST))) -MMD -MP \
	-Wall -Wextra -Wno-unused-parameter -Wno-unused-function -Wno-type-limits -Wno-parentheses -Wno-unused-value -Wno-self-assign
OBJS := $(patsubst $(GEN)/%.c,$(OBJ)/%.o,$(wildcard $(GEN)/*.c))

$(OBJ)/samaltak.elf: $(OBJS)
	$(UEFI_LD) -pie --no-dynamic-linker -z norelro -e efi_main -o $@ $(OBJS)

$(OBJ)/%.o: $(GEN)/%.c
	@mkdir -p $(OBJ)
	$(if $(BRIEF),@echo "cc   $<";) $(UEFI_CC) $(UEFI_CFLAGS) -c -o $@ $<

-include $(OBJS:.o=.d)
