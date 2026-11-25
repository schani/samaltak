# Samaltak: VM, seed image (the Smalltalk ImageBuilder, run in boot/seed.image), full image (stage 2), tests.
# OUT selects the build directory, so concurrent builds do not collide: make image OUT=build/me
OUT ?= build

VM := vm/build/samaltak

all: vm seed image runtime

vm:
	$(MAKE) -C vm

seed: vm
	boot/build-image.sh src $(OUT)/seed.image

image: vm seed
	$(VM) $(OUT)/seed.image --headless --stage2 $(OUT)/samaltak.image

# The runtime image applications run on (bin/samaltak run, docs/apps.md): the packages of src/runtime.txt, lean on fonts.
runtime: vm
	PACKAGES=src/runtime.txt boot/build-image.sh src $(OUT)/runtime-seed.image
	$(VM) $(OUT)/runtime-seed.image --headless --stage2 $(OUT)/runtime.image --runtime

fresh-runtime: vm
	@[ -f $(OUT)/runtime.image ] && [ -z "$$(find src boot $(VM) -newer $(OUT)/runtime.image | head -1)" ] || $(MAKE) runtime

# The image, rebuilt only if src/, boot/ or the VM are newer, so an image saved from the World menu stays.
fresh-image: vm
	@[ -f $(OUT)/samaltak.image ] && [ -z "$$(find src boot $(VM) -newer $(OUT)/samaltak.image | head -1)" ] || $(MAKE) image

# Start the system.
run: fresh-image
	$(VM) $(OUT)/samaltak.image

test-vm: vm
	vm/tests/run.sh

# After changing the VM's Lowtalk sources (src/VM-Core, src/VM-Platform): translate them into vm/gen (checked in).
translate: image
	$(VM) $(OUT)/samaltak.image --headless --eval "[VMTranslator generateVM. 'ok'] on: Error do: [:e | e messageText]"
	$(MAKE) -C vm

# The image's tests under each JIT, every method compiled on its first activation (under opt also optimized after
# one more, and again with deoptimization stress); Tests-Kernel also with a code cache small enough to flush
# repeatedly. Use 3 MB on x86-64 to avoid pathological recompilation.
STRESS_CACHE_MB := $(if $(filter x86_64 amd64,$(shell uname -m)),3,1)
test-jit: image
	$(MAKE) test-jit-none
	$(MAKE) test-jit-baseline
	$(MAKE) test-jit-opt
	$(MAKE) test-jit-deopt
	$(MAKE) test-jit-cache
test-jit-none: image
	tests/st_suite.sh $(OUT)/samaltak.image --jit none
test-jit-baseline: image
	tests/st_suite.sh $(OUT)/samaltak.image --jit baseline --jit-threshold 0
test-jit-opt: image
	tests/vm/bound_ffi_site_test.sh $(OUT)/samaltak.image $(VM)
	tests/st_suite.sh $(OUT)/samaltak.image --jit opt --jit-threshold 0 --jit-flags eager
test-jit-deopt: image
	tests/st_suite.sh $(OUT)/samaltak.image --jit opt --jit-threshold 0 --jit-flags eager,deopt
test-jit-cache: image
	tests/st_suite.sh $(OUT)/samaltak.image --jit opt --jit-threshold 0 --jit-cache $(STRESS_CACHE_MB) --jit-flags eager,notes -- Tests-Kernel

# Everything, in stages (CI runs them as separate jobs); any failure, skipped test or headless-only VM fails it. The UI
# scripts use a hidden window.
test: test-core
	$(MAKE) test-ffi-headless
	$(MAKE) test-ffi-no-platform
	$(MAKE) test-jit
	$(MAKE) test-tools
	$(MAKE) test-uefi
	@echo "make test: all passed"
PLATFORM_CHECK = @[ -f vm/build/.variant-platform ] || { echo "make test: FAILED: the VM was built without the platform layer (SDL3), UI tests would not run"; exit 1; }
test-core: image test-vm
	$(PLATFORM_CHECK)
	tests/vm/gen_test.sh $(OUT)/samaltak.image
	tests/vm/runtime_native_grants_test.sh $(OUT)/samaltak.image $(VM)
	tests/vm/wrapped_ffi_specialization_test.sh $(OUT)/samaltak.image $(VM)
	tests/vm/ffi_external_notification_test.sh $(OUT)/samaltak.image $(VM)
	tests/boot/layering_test.sh
	tests/boot/fresh_seed_test.sh $(VM)
	tests/st_suite.sh $(OUT)/samaltak.image
	SAMALTAK_VERIFY_GC=1 tests/st_suite.sh $(OUT)/samaltak.image --eden 1 -- Tests-Kernel Tests-Compiler
	$(MAKE) fresh-runtime
	tests/st_suite.sh $(OUT)/runtime.image -- Weather --load apps/Weather
	tests/st_suite.sh $(OUT)/runtime.image -- Agents --load apps/Agents
	tests/st_suite.sh $(OUT)/runtime.image -- Wodify --load apps/Wodify
# Native-entry and semantic smoke, not the performance gate (shared CI CPUs are noisy).
test-ffi-bigint-owned: image
	tests/vm/bigint_owned_ffi_test.sh "$(OUT)/samaltak.image" "$(VM)" "$(OUT)/ffi-bigint-owned-logs"

FFI_HEADLESS_LOGS ?= $(OUT)/ffi-headless-logs
FFI_NO_PLATFORM_LOGS ?= $(OUT)/ffi-no-platform-logs
FFI_NO_PLATFORM_VM := vm/build/ffi-no-platform/samaltak
FFI_NO_VIDEO = env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY -u SAMALTAK_NATIVE_GRANTS SDL_VIDEO_DRIVER=ffi_no_video SDL_VIDEODRIVER=ffi_no_video

test-ffi-headless: image test-ffi-bigint-owned
	$(PLATFORM_CHECK)
	mkdir -p "$(FFI_HEADLESS_LOGS)"
	python3 tests/vm/ffi_cutover.py check "$(OUT)/samaltak.image" "$(VM)" --backend sdl --logs "$(FFI_HEADLESS_LOGS)"
	tests/vm/ffi_migration_manifest_test.sh $(OUT)/samaltak.image $(VM)
	tests/vm/ffi_migration_gate_test.sh $(OUT)/samaltak.image $(VM) sdl release
	tests/vm/ffi_migration_owned_test.sh $(OUT)/samaltak.image $(VM) sdl release
	tests/vm/file_ffi_snapshot_test.sh $(OUT)/samaltak.image $(VM)
	tests/vm/core_getenv_large_test.sh $(OUT)/samaltak.image $(VM)
	python3 tests/vm/core_ffi_test.py $(OUT)/samaltak.image $(VM) --trace --logs "$(FFI_HEADLESS_LOGS)/core"
	tests/vm/window_ffi_test.sh $(OUT)/samaltak.image $(VM) --logs "$(FFI_HEADLESS_LOGS)"
	@set -eu; for mode in none baseline opt; do \
		flags=; [ "$$mode" != opt ] || flags='--jit-flags eager'; \
		log="$(FFI_HEADLESS_LOGS)/file-$$mode.log"; \
		$(FFI_NO_VIDEO) SAMALTAK_FFI_NATIVE_TRACE=1 tests/st_suite.sh "$(OUT)/samaltak.image" \
			--jit "$$mode" --jit-threshold 0 $$flags -- FileFFITest ApprovedFFIRegistryTest FFISeededSiteTest >"$$log" 2>&1 \
			|| { cat "$$log"; exit 1; }; \
		python3 tests/vm/socket_ffi_test.py $(VM) $(OUT)/samaltak.image --jit "$$mode" --trace --logs "$(FFI_HEADLESS_LOGS)"; \
	done
	python3 tests/vm/process_ffi_test.py "$(OUT)/samaltak.image" "$(VM)" --logs "$(FFI_HEADLESS_LOGS)"
	python3 tests/vm/ffi_exec_probe_test.py "$(OUT)/samaltak.image" "$(VM)"
	python3 tests/vm/ffi_cutover.py coverage --profile hosted-headless \
		--none "$(FFI_HEADLESS_LOGS)/core/none.stderr" "$(FFI_HEADLESS_LOGS)/file-none.log" "$(FFI_HEADLESS_LOGS)/window-none.stderr" "$(FFI_HEADLESS_LOGS)/socket-none.stderr" "$(OUT)/ffi-bigint-owned-logs/production-none.err" "$(FFI_HEADLESS_LOGS)/process-none.stderr" "$(FFI_HEADLESS_LOGS)/exec-none.stderr" \
		--baseline "$(FFI_HEADLESS_LOGS)/core/baseline.stderr" "$(FFI_HEADLESS_LOGS)/file-baseline.log" "$(FFI_HEADLESS_LOGS)/window-baseline.stderr" "$(FFI_HEADLESS_LOGS)/socket-baseline.stderr" "$(OUT)/ffi-bigint-owned-logs/production-baseline.err" "$(FFI_HEADLESS_LOGS)/process-baseline.stderr" "$(FFI_HEADLESS_LOGS)/exec-baseline.stderr" \
		--opt "$(FFI_HEADLESS_LOGS)/core/opt.stderr" "$(FFI_HEADLESS_LOGS)/file-opt.log" "$(FFI_HEADLESS_LOGS)/window-opt.stderr" "$(FFI_HEADLESS_LOGS)/socket-opt.stderr" "$(OUT)/ffi-bigint-owned-logs/production-opt.err" "$(FFI_HEADLESS_LOGS)/process-opt.stderr" "$(FFI_HEADLESS_LOGS)/exec-opt.stderr"
	@logs=$$(mktemp -d "$(FFI_HEADLESS_LOGS)/paired.XXXXXXXX"); \
		python3 vm/tests/bench/ffi-paired.py --vm $(VM) --image $(OUT)/samaltak.image --logs "$$logs" --proof-only

test-ffi-no-platform: image
	$(MAKE) -C vm BUILD=build/ffi-no-platform NO_PLATFORM=1
	mkdir -p "$(FFI_NO_PLATFORM_LOGS)"
	python3 tests/vm/ffi_cutover.py check "$(OUT)/samaltak.image" "$(FFI_NO_PLATFORM_VM)" --backend no-platform --logs "$(FFI_NO_PLATFORM_LOGS)"
	tests/vm/ffi_migration_gate_test.sh $(OUT)/samaltak.image $(FFI_NO_PLATFORM_VM) no-platform release
	python3 tests/vm/core_ffi_test.py $(OUT)/samaltak.image $(FFI_NO_PLATFORM_VM) --trace --logs "$(FFI_NO_PLATFORM_LOGS)/core"
	tests/vm/bigint_owned_ffi_test.sh "$(OUT)/samaltak.image" "$(FFI_NO_PLATFORM_VM)" "$(FFI_NO_PLATFORM_LOGS)"
	python3 tests/vm/ffi_cutover.py coverage --profile no-platform \
		--none "$(FFI_NO_PLATFORM_LOGS)/core/none.stderr" "$(FFI_NO_PLATFORM_LOGS)/production-none.err" \
		--baseline "$(FFI_NO_PLATFORM_LOGS)/core/baseline.stderr" "$(FFI_NO_PLATFORM_LOGS)/production-baseline.err" \
		--opt "$(FFI_NO_PLATFORM_LOGS)/core/opt.stderr" "$(FFI_NO_PLATFORM_LOGS)/production-opt.err"

# Only this target builds a VM with test exports; use a separate object tree and binary.
test-ffi-gpu-paged: image
	$(PLATFORM_CHECK)
	$(MAKE) -C vm BUILD=build/ffi-test-exports CPPFLAGS="$(CPPFLAGS) -DSAMALTAK_FFI_TEST_EXPORTS=1"
	@set -eu; unset DISPLAY WAYLAND_DISPLAY XAUTHORITY SAMALTAK_NATIVE_GRANTS; \
		export LC_ALL=C SDL_VIDEO_DRIVER=ffi_no_video SDL_VIDEODRIVER=ffi_no_video; \
		result=$$(SAMALTAK_FFI_TEST_EXPORTS=1 $(VM) "$(OUT)/samaltak.image" --headless \
			--eval "(PlatformFFI bind: #(call 'platform' 'platform_gpu_test_shader_pages' (writableBytesWithLength) i32)) isNil"); \
		test "$$result" = true || { echo "Release VM did not deny the paged shader fixture: $$result" >&2; exit 1; }; \
		for mode in none baseline opt; do \
			echo "Paged shader fixture: $$mode"; \
			result=$$(vm/build/ffi-test-exports/samaltak \
				--jit "$$mode" --jit-threshold 0 --jit-flags eager "$(OUT)/samaltak.image" --headless \
				--eval "$$(cat tests/vm/gpu_shader_paged_test.st)"); \
			test "$$result" = true || { printf '%s\n' "$$result" >&2; exit 1; }; \
		done

# Run only in display CI (real SDL window + software Vulkan through the test runner's X server).
FFI_DISPLAY_LOGS ?= $(OUT)/ffi-display-logs
test-ffi-display: image
	@test "$$GITHUB_ACTIONS" = true && test -n "$$DISPLAY"
	mkdir -p "$(FFI_DISPLAY_LOGS)"
	tests/vm/window_ffi_test.sh $(OUT)/samaltak.image $(VM) --display-ci --logs "$(FFI_DISPLAY_LOGS)"
	@set -eu; for mode in none baseline opt; do \
		flags=; [ "$$mode" != opt ] || flags='--jit-flags eager'; \
		log="$(FFI_DISPLAY_LOGS)/gpu-$$mode.log"; \
		SAMALTAK_FFI_NATIVE_TRACE=1 tests/st_suite.sh "$(OUT)/samaltak.image" --jit "$$mode" --jit-threshold 0 \
			$$flags -- GPUFFIRegressionTest >"$$log" 2>&1 || { cat "$$log"; exit 1; }; \
	done
	python3 tests/vm/ffi_cutover.py coverage --profile display \
		--none "$(FFI_DISPLAY_LOGS)/gpu-none.log" "$(FFI_DISPLAY_LOGS)/window-none.stderr" \
		--baseline "$(FFI_DISPLAY_LOGS)/gpu-baseline.log" "$(FFI_DISPLAY_LOGS)/window-baseline.stderr" \
		--opt "$(FFI_DISPLAY_LOGS)/gpu-opt.log" "$(FFI_DISPLAY_LOGS)/window-opt.stderr"
	@logs=$$(mktemp -d "$(FFI_DISPLAY_LOGS)/paired.XXXXXXXX"); \
		python3 vm/tests/bench/ffi-paired.py --vm $(VM) --image $(OUT)/samaltak.image \
			--logs "$$logs" --display-ci --proof-only

test-tools: image
	$(PLATFORM_CHECK)
	$(MAKE) -C vm/platform test st-test
	tests/remote/cli_test.sh $(OUT)/samaltak.image
	tests/remote/auth_test.sh $(OUT)/samaltak.image
	tests/remote/recording_test.sh $(OUT)/samaltak.image
	tests/tools/desktop_test.sh $(OUT)/samaltak.image
	tests/tools/snapshot_test.sh $(OUT)/samaltak.image
	tests/tools/reboot_test.sh $(OUT)/samaltak.image
	tests/tools/quit_signal_test.sh $(OUT)/samaltak.image

# The VM as a UEFI application for x86-64 or arm64 (UEFI_ARCH, this machine's by default), translated from the
# same Lowtalk with VM-UEFI in place of the C library (docs/uefi.md): $(UEFI)/esp is a boot volume with it
# (EFI/BOOT/BOOTX64.EFI or BOOTAA64.EFI) and samaltak.args (the command line, an argument a line), $(UEFI)/image.disk a
# disk with the image (UefiImageStore: two slots, snapshots go to the other), each rebuilt only if the image is newer,
# so a snapshot stays. uefi-run boots them in QEMU with its UEFI
# firmware, on this machine's CPU if it is UEFI_ARCH (KVM, or Hypervisor.framework on macOS), and fails unless the VM
# exits 0; UEFI_ARGS are its arguments after the image (disk:). uefi-ui boots the World in a QEMU window (USB keyboard,
# virtio tablet; the console on stdio). uefi-control boots it without a window, its control service (--control on
# 0.0.0.0 in the guest) forwarded from 127.0.0.1:UEFI_CONTROL_PORT (samaltak-ctl open --uefi). It reads the CLI's
# UEFI_CONTROL_TOKEN from the environment into owner-only samaltak.args, never onto a host command line. If unset,
# the guest generates and displays a token using firmware entropy (QEMU's virtio-rng).
# The guest's network is QEMU's user network (NAT, DHCP, DNS) on a UEFI_NIC without its option ROM, which the image
# drives: e1000e on x86-64 (q35's default), virtio-net-pci on arm64 (virt's). test-uefi runs the tests there that need no platform layer (no files, processes
# or ptys from Smalltalk), opens the World on the firmware's screen and moves its pointer by remote input, drives the VM with
# samaltak-ctl and has it connect to itself through the host (10.0.2.2: QEMU's host), once to ping, once to move a megabyte
# each way (test-uefi-nic: on a virtio-net-pci too if UEFI_NIC is another, once to ping), snapshots and resumes.
comma := ,
UEFI_HOST_ARCH := $(if $(filter x86_64 amd64,$(shell uname -m)),x86_64,arm64)
UEFI_ARCH ?= $(UEFI_HOST_ARCH)
UEFI := $(OUT)/uefi-$(UEFI_ARCH)
UEFI_ARGS ?= --headless --eval 'Smalltalk vmBanner'
UEFI_HEAP_MB ?= 256
UEFI_SCREEN ?= 1024x768
ifeq ($(shell uname -s),Darwin)
UEFI_DISPLAY := -display cocoa,zoom-to-fit=on
UEFI_WINDOW := osascript tools/qemu-window.applescript $(subst x, ,$(UEFI_SCREEN)) &
endif
UEFI_DISK_MB ?= 512
UEFI_ACCEL := $(if $(filter $(UEFI_HOST_ARCH),$(UEFI_ARCH)),$(if $(wildcard /dev/kvm),-accel kvm -cpu host,$(if $(filter Darwin,$(shell uname -s)),-accel hvf -cpu host)))
ifeq ($(UEFI_ARCH),arm64)
UEFI_TARGET := aarch64
UEFI_BOOT := BOOTAA64.EFI
OVMF_CODE ?= $(firstword $(wildcard /usr/share/AAVMF/AAVMF_CODE.fd /opt/homebrew/share/qemu/edk2-aarch64-code.fd /usr/share/qemu/edk2-aarch64-code.fd))
OVMF_VARS ?= $(firstword $(wildcard /usr/share/AAVMF/AAVMF_VARS.fd /opt/homebrew/share/qemu/edk2-arm-vars.fd /usr/share/qemu/edk2-arm-vars.fd))
QEMU_UEFI_MACHINE := qemu-system-aarch64 -machine virt $(or $(UEFI_ACCEL),-cpu max) -device ramfb
UEFI_NIC ?= virtio-net-pci
else
UEFI_TARGET := x86_64
UEFI_BOOT := BOOTX64.EFI
OVMF_CODE ?= $(firstword $(wildcard /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /opt/homebrew/share/qemu/edk2-x86_64-code.fd /usr/share/qemu/edk2-x86_64-code.fd))
OVMF_VARS ?= $(firstword $(wildcard /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd /opt/homebrew/share/qemu/edk2-i386-vars.fd /usr/share/qemu/edk2-i386-vars.fd))
QEMU_UEFI_MACHINE := qemu-system-x86_64 -machine q35 $(UEFI_ACCEL)
UEFI_NIC ?= e1000e
endif
QEMU_UEFI = $(QEMU_UEFI_MACHINE) -m 2048 -no-reboot \
	-nic user,model=$(UEFI_NIC)$(if $(UEFI_CONTROL_PORT),$(comma)hostfwd=tcp:127.0.0.1:$(UEFI_CONTROL_PORT)-:7341) -global $(UEFI_NIC).romfile= \
	-device virtio-rng-pci -drive if=pflash,format=raw,readonly=on,file=$(OVMF_CODE) -drive if=pflash,format=raw,file=$(UEFI)/vars.fd \
	-drive format=raw,file=fat:rw:$(UEFI)/esp -drive format=raw,file=$(UEFI)/image.disk
uefi: fresh-image
	$(MAKE) $(UEFI)/esp/EFI/BOOT/$(UEFI_BOOT) $(UEFI)/image.disk
$(UEFI)/esp/EFI/BOOT/$(UEFI_BOOT): $(OUT)/samaltak.image vm/uefi.mk
	rm -rf $(UEFI)/gen
	mkdir -p $(UEFI)/esp/EFI/BOOT
	$(VM) $(OUT)/samaltak.image --headless --eval "[VMTranslator generateVMInto: '$(UEFI)/gen' os: #uefi arch: #$(UEFI_ARCH). 'ok'] on: Error do: [:e | Transcript show: e messageText; cr. Smalltalk quit: 1]"
	$(MAKE) -f vm/uefi.mk GEN=$(UEFI)/gen OBJ=$(UEFI)/obj UEFI_TARGET=$(UEFI_TARGET)
	$(VM) $(OUT)/samaltak.image --headless --eval "UefiImageWriter new convert: '$(UEFI)/obj/samaltak.elf' to: '$(UEFI)/esp/EFI/BOOT/$(UEFI_BOOT)'"
$(UEFI)/image.disk: $(OUT)/samaltak.image
	$(VM) $(OUT)/samaltak.image --headless --eval "UefiImageDisk new write: '$(OUT)/samaltak.image' to: '$(UEFI)/image.disk'"
	truncate -s $(UEFI_DISK_MB)M $(UEFI)/image.disk
uefi-run: uefi
	$(MAKE) uefi-boot
# Recreate rather than truncate: umask does not change an existing file's mode.
UEFI_ARGS_FILE := $(UEFI)/esp/samaltak.args
UEFI_WRITE_ARGS = rm -f "$(UEFI_ARGS_FILE)" && umask 077 && set -C && printf '%s\n'
uefi-boot:
	$(UEFI_WRITE_ARGS) --max-heap $(UEFI_HEAP_MB) disk: $(UEFI_ARGS) > "$(UEFI_ARGS_FILE)"
	cp $(OVMF_VARS) $(UEFI)/vars.fd
	$(QEMU_UEFI) -nographic | tee $(UEFI)/console.log
	@grep -q 'samaltak: exit 0' $(UEFI)/console.log
uefi-ui: uefi
	$(UEFI_WRITE_ARGS) --max-heap $(UEFI_HEAP_MB) disk: --window-size $(UEFI_SCREEN) > "$(UEFI_ARGS_FILE)"
	cp $(OVMF_VARS) $(UEFI)/vars.fd
	$(UEFI_WINDOW) $(QEMU_UEFI) $(UEFI_DISPLAY) $(if $(filter x86_64,$(UEFI_ARCH)),-vga std) -device qemu-xhci -device usb-kbd -device virtio-tablet-pci -serial stdio
uefi-control: uefi
	@set +x; $(UEFI_WRITE_ARGS) --max-heap $(UEFI_HEAP_MB) disk: --control --control-host 0.0.0.0 --control-port 7341 \
		$${UEFI_CONTROL_TOKEN:+--control-token "$$UEFI_CONTROL_TOKEN"} $(UEFI_CONTROL_ARGS) > "$(UEFI_ARGS_FILE)"
	cp $(OVMF_VARS) $(UEFI)/vars.fd
	$(QEMU_UEFI) -display none $(if $(filter x86_64,$(UEFI_ARCH)),-vga std) -device qemu-xhci -device usb-kbd -device virtio-tablet-pci -serial stdio
UEFI_TESTS := CompilerTest ParserTest ScannerTest ClassTest CollectionTest ContextTest ExceptionTest FloatTest FractionTest \
	HashingTest ImmutabilityTest IntegerTest LazyContextTest MarriedContextTest MessageNotUnderstoodTest ObjectTest ProcessTest \
	StackOverflowTest StreamTest StringSearchTest StringTest SymbolTest SystemChangesTest SystemTest UnicodeTest WorkClockTest \
	Amd64DisassemblerTest Arm64DisassemblerTest ByteSearchTest FFIBindingTest
UEFI_WORLD := | w t | w := UIWindows startUp. RemoteInputDevice default inject: {1. nil. 123. 45. 0. 0. nil. w displayWindow windowId}. t := Time millisecondClockValue. [w dispatcher pointer = (123 @ 45) or: [Time millisecondClockValue - t > 20000]] whileFalse: [(Delay forMilliseconds: 50) wait]. Smalltalk vm stderrWrite: 'world ', w extent printString, ' ', Renderer default device isSoftware printString, ' ', w dispatcher pointer rounded printString, (String with: Character lf)
# Resolve the credential in the guest's boot arguments; the host client's argv gets only this expression.
UEFI_NET_AUTH := (Smalltalk argumentAfter: '--control-token')
UEFI_NET := | s buf n | s := RemoteSocket connectTo: '10.0.2.2' port: $$P timeout: 20000. s sendAll: '{\"cmd\": \"ping\", \"auth\": \"', $(UEFI_NET_AUTH), '\"}', (String with: Character lf). buf := ByteArray new: 200. n := s receiveInto: buf timeout: 20000. s close. (buf copyFrom: 1 to: n) asString
UEFI_NET_BULK := | src req s buf n chunk out t ms resp ok more | src := String new: 1000000. 1 to: src size do: [:i | src at: i put: (Character value: 97 + (i * 7 rem: 26))]. req := '{\"cmd\": \"eval\", \"auth\": \"', $(UEFI_NET_AUTH), '\", \"source\": \"''', src, ''' reverse\"}', (String with: Character lf). t := Time millisecondClockValue. s := RemoteSocket connectTo: '10.0.2.2' port: $$P timeout: 20000. s sendAll: req. out := WriteStream on: (String new: 1100000). buf := ByteArray new: 65536. more := true. [more] whileTrue: [n := s receiveInto: buf timeout: 60000. chunk := (buf copyFrom: 1 to: n) asString. out nextPutAll: chunk. more := n > 0 and: [(chunk includes: Character lf) not]]. ms := Time millisecondClockValue - t. s close. resp := out contents. ok := (resp includesSubstring: '\"ok\":true') and: [resp includesSubstring: src reverse]. 'bulk ', ok printString, ' ', (req size + resp size) printString, ' bytes in ', ms printString, ' ms'
UEFI_NET_DRIVER := 'driver ', NetworkStack active interface class name
UEFI_DRIVER = $(if $(filter e1000e,$(1)),E1000eInterface,VirtioNetInterface)
UEFI_SNAPSHOT := Smalltalk at: 'UefiMark' asSymbol put: 42. (Smalltalk snapshot: Smalltalk vm imagePath) ifTrue: ['resumed ', (Smalltalk at: 'UefiMark' asSymbol) printString] ifFalse: ['saved']
test-uefi:
	rm -f $(UEFI)/image.disk
	$(MAKE) uefi-run UEFI_ARGS='--headless --test $(UEFI_TESTS)'
	$(MAKE) uefi-boot UEFI_ARGS="--headless --eval \"$$(tr '\n' ' ' < tests/boot/uefi_cutover.st)\""
	grep -Fq 'UEFI cutover OK' $(UEFI)/console.log
	grep -Fq 'UEFI-stdout-π' $(UEFI)/console.log
	grep -Fq 'UEFI-stderr-é' $(UEFI)/console.log
	$(MAKE) uefi-boot UEFI_ARGS="--eval \"$(UEFI_WORLD)\""
	grep -qE "^world [0-9]+@[0-9]+ true 123@45" $(UEFI)/console.log
	$(call UEFI_NET_TEST,bulk)
	$(if $(filter-out virtio-net-pci,$(UEFI_NIC)),$(MAKE) test-uefi-nic UEFI_NIC=virtio-net-pci)
	$(MAKE) uefi-boot UEFI_ARGS="--headless --eval \"$(UEFI_SNAPSHOT)\""
	grep -q "'saved'" $(UEFI)/console.log
	$(MAKE) uefi-boot UEFI_ARGS=--headless
	grep -q "'resumed 42'" $(UEFI)/console.log
	rm $(UEFI)/image.disk
test-uefi-nic:
	$(call UEFI_NET_TEST,ping)

define UEFI_NET_TEST
	@set -eu; \
	S=uefi-test-$$$$; \
	OUT=$(OUT) UEFI_NIC=$(UEFI_NIC) SAMALTAK_CONTROL_PORT= tools/samaltak-ctl --session "$$S" open --uefi --headless; \
	trap 'tools/samaltak-ctl --session "$$S" close; cat "$(UEFI)/net.log"' EXIT; \
	P=$$(sed -n 's/.*"port": *\([0-9]*\).*/\1/p' "$${TMPDIR:-/tmp}/samaltak-ctl/$$S.json"); \
	tools/samaltak-ctl --session "$$S" eval "$(UEFI_NET_DRIVER)" > "$(UEFI)/net.log"; \
	$(if $(filter bulk,$(1)),tests/remote/auth_test.sh --session "$$S" >> "$(UEFI)/net.log";) \
	tools/samaltak-ctl --session "$$S" eval "$(UEFI_NET)" >> "$(UEFI)/net.log"; \
	$(if $(filter bulk,$(1)),tools/samaltak-ctl --session "$$S" eval "$(UEFI_NET_BULK)" >> "$(UEFI)/net.log"; grep -q "'bulk true" "$(UEFI)/net.log";) \
	grep -Fq '"pong":true' "$(UEFI)/net.log"; \
	grep -q "'driver $(call UEFI_DRIVER,$(UEFI_NIC))'" "$(UEFI)/net.log"
endef

# The narrated walkthrough on the real system, from a copy of the image named nuuk.image like the prototype's (a visible window; needs ffmpeg, agent-browser for the captions and
# ELEVENLABS_API_KEY in .env unless the clips in $(VIDEO)/narration are cached).
VIDEO ?= .context/video-real
video: vm image
	cp $(OUT)/samaltak.image $(OUT)/nuuk.image
	node tools/narrate.mjs $(VIDEO)
	WALKTHROUGH_IMAGE=$(OUT)/nuuk.image node tools/walkthrough.mjs $(VIDEO)
	python3 tools/compose-video.py $(VIDEO)
	cp $(VIDEO)/walkthrough.mp4 docs/media/walkthrough.mp4

# The "mind blown" video (.context/mindblown.md): the same pipeline, steps in tools/mindblown/narration.json, voice
# Matilda, unperformed (no style exaggeration, lines spoken as one conversation). The snapshot beat saves the image and
# relaunches it, so it runs on its own copy of the image.
MINDBLOWN ?= .context/video-mindblown
MINDBLOWN_VOICE ?= XrExE9yKIg1WjnnlVkGX
MINDBLOWN_REQUEST ?= {"voice_settings": {"stability": 0.35, "similarity_boost": 0.7, "style": 0, "use_speaker_boost": true, "speed": 1.05}, "continuity": true}
mindblown-video: vm image
	cp $(OUT)/samaltak.image $(OUT)/nuuk.image
	ELEVENLABS_VOICE=$(MINDBLOWN_VOICE) ELEVENLABS_REQUEST='$(MINDBLOWN_REQUEST)' node tools/narrate.mjs $(MINDBLOWN) tools/mindblown/narration.json
	WALKTHROUGH_IMAGE=$(OUT)/nuuk.image node tools/mindblown/walkthrough-mindblown.mjs $(MINDBLOWN)
	python3 tools/compose-video.py $(MINDBLOWN) mindblown.mp4
	cp $(MINDBLOWN)/mindblown.mp4 docs/media/mindblown.mp4

# The JIT video: the same pipeline, steps in tools/jit/narration.json, the mind-blown voice. The race needs Pharo 12
# (vm/tests/bench/awfy.sh --pharo, /tmp/pharo-dl).
JIT_VIDEO ?= .context/video-jit
jit-video: vm image
	cp $(OUT)/samaltak.image $(OUT)/nuuk.image
	ELEVENLABS_VOICE=$(MINDBLOWN_VOICE) ELEVENLABS_REQUEST='$(MINDBLOWN_REQUEST)' node tools/narrate.mjs $(JIT_VIDEO) tools/jit/narration.json
	WALKTHROUGH_IMAGE=$(OUT)/nuuk.image node tools/jit/walkthrough-jit.mjs $(JIT_VIDEO)
	python3 tools/compose-video.py $(JIT_VIDEO) jit.mp4
	cp $(JIT_VIDEO)/jit.mp4 docs/media/jit.mp4

clean:
	$(MAKE) -C vm clean
	rm -rf build vm/build/ffi-test-exports vm/build/ffi-no-platform

.PHONY: all vm seed image fresh-image run translate uefi uefi-run uefi-boot uefi-ui uefi-control test-uefi test-uefi-nic test-vm test-jit test-jit-none test-jit-baseline test-jit-opt test-jit-deopt test-jit-cache test-core test-tools test video mindblown-video jit-video clean

.PHONY: test-ffi-bigint-owned test-ffi-gpu-paged test-ffi-headless test-ffi-no-platform test-ffi-display
