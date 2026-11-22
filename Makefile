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
# one more, and again with deoptimization stress); Tests-Kernel also with a code cache small enough to be flushed
# again and again (x86-64's code is a third bigger than arm64's: in 1 MB it thrashes so hard that the slowest tests
# time out, 2 MB still flushes hundreds of times).
STRESS_CACHE_MB := $(if $(filter x86_64 amd64,$(shell uname -m)),2,1)
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
	tests/st_suite.sh $(OUT)/samaltak.image --jit opt --jit-threshold 0 --jit-flags eager
test-jit-deopt: image
	tests/st_suite.sh $(OUT)/samaltak.image --jit opt --jit-threshold 0 --jit-flags eager,deopt
test-jit-cache: image
	tests/st_suite.sh $(OUT)/samaltak.image --jit opt --jit-threshold 0 --jit-cache $(STRESS_CACHE_MB) --jit-flags eager,notes -- Tests-Kernel

# Everything, in stages (CI runs them as separate jobs); any failure, skipped test or headless-only VM fails it. The UI
# scripts use a hidden window.
test: test-core
	$(MAKE) test-jit
	$(MAKE) test-tools
	$(MAKE) test-uefi
	@echo "make test: all passed"
PLATFORM_CHECK = @[ -f vm/build/.variant-platform ] || { echo "make test: FAILED: the VM was built without the platform layer (SDL3), UI tests would not run"; exit 1; }
test-core: image test-vm test-c4
	$(PLATFORM_CHECK)
	tests/vm/gen_test.sh $(OUT)/samaltak.image
	tests/boot/layering_test.sh
	tests/st_suite.sh $(OUT)/samaltak.image
	SAMALTAK_VERIFY_GC=1 SAMALTAK_VERIFY_MARK=1 tests/st_suite.sh $(OUT)/samaltak.image --eden 1 -- Tests-Kernel Tests-Compiler
	$(MAKE) fresh-runtime
	tests/st_suite.sh $(OUT)/runtime.image -- Weather --load apps/Weather
	tests/st_suite.sh $(OUT)/runtime.image -- Agents --load apps/Agents
	tests/st_suite.sh $(OUT)/runtime.image -- Wodify --load apps/Wodify

test-c4: image
	tests/st_suite.sh "$(OUT)/samaltak.image" -- C4HeapTest --load apps/C4Prototype
	@log=$$(mktemp "$(OUT)/c4-mark.XXXXXX") || exit; trap 'rm -f "$$log"' 0; rc=0; \
		SAMALTAK_VERIFY_GC=1 SAMALTAK_VERIFY_MARK=1 tests/st_suite.sh "$(OUT)/samaltak.image" --eden 1 -- C4-MarkTests --load tests/vm/C4MarkTest.st >"$$log" 2>&1 || rc=$$?; \
		cat "$$log"; [ "$$rc" -eq 0 ] || exit "$$rc"; \
		awk '$$0 == "samaltak: verify mark: full GC matched" { n++ } END { exit n != 1 }' "$$log" || { echo 'test-c4: expected exactly one native mark witness' >&2; exit 1; }
ifeq ($(shell uname -s -m),Linux x86_64)
	OUT="$(OUT)" VM="$(VM)" tests/vm/c4-native/run.sh "$(OUT)/samaltak.image"
	tests/vm/c4-live/run-engine.sh
	OUT="$(OUT)" VM="$(VM)" tests/vm/c4-live/run.sh
	OUT="$(OUT)" tests/vm/c4-live/run-weak.sh "$(OUT)/samaltak.image"
	OUT="$(OUT)" tests/vm/c4-live/run-moving.sh "$(OUT)/samaltak.image"
	OUT="$(OUT)" tests/vm/c4-live/run-context.sh "$(OUT)/samaltak.image"
	OUT="$(OUT)" tests/vm/c4-live/run-low-cap.sh "$(OUT)/samaltak.image"
	OUT="$(OUT)" tests/vm/c4-live/run-become.sh "$(OUT)/samaltak.image"
endif

test-c4-live:
	tests/vm/c4-live/run-engine.sh
	OUT="$(OUT)" tests/vm/c4-live/run.sh

test-tools: image
	$(PLATFORM_CHECK)
	$(MAKE) -C vm/platform test st-test
	tests/remote/cli_test.sh $(OUT)/samaltak.image
	tests/remote/recording_test.sh $(OUT)/samaltak.image
	tests/tools/desktop_test.sh $(OUT)/samaltak.image
	tests/tools/snapshot_test.sh $(OUT)/samaltak.image
	tests/tools/reboot_test.sh $(OUT)/samaltak.image

# The VM as a UEFI application for x86-64 or arm64 (UEFI_ARCH, this machine's by default), translated from the
# same Lowtalk with VM-UEFI in place of the C library (docs/uefi.md): $(UEFI)/esp is a boot volume with it
# (EFI/BOOT/BOOTX64.EFI or BOOTAA64.EFI) and samaltak.args (the command line, an argument a line), $(UEFI)/image.disk a
# disk with the image (UefiImageStore: two slots, snapshots go to the other), each rebuilt only if the image is newer,
# so a snapshot stays. uefi-run boots them in QEMU with its UEFI
# firmware, on this machine's CPU if it is UEFI_ARCH (KVM, or Hypervisor.framework on macOS), and fails unless the VM
# exits 0; UEFI_ARGS are its arguments after the image (disk:). uefi-ui boots the World in a QEMU window (USB keyboard,
# virtio tablet; the console on stdio). uefi-control boots it without a window, its control service (--control on
# 0.0.0.0 in the guest) forwarded from 127.0.0.1:UEFI_CONTROL_PORT, UEFI_CONTROL_ARGS after it (samaltak-ctl open --uefi).
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
	-drive if=pflash,format=raw,readonly=on,file=$(OVMF_CODE) -drive if=pflash,format=raw,file=$(UEFI)/vars.fd \
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
uefi-boot:
	printf '%s\n' --max-heap $(UEFI_HEAP_MB) disk: $(UEFI_ARGS) > $(UEFI)/esp/samaltak.args
	cp $(OVMF_VARS) $(UEFI)/vars.fd
	$(QEMU_UEFI) -nographic | tee $(UEFI)/console.log
	@grep -q 'samaltak: exit 0' $(UEFI)/console.log
uefi-ui: uefi
	printf '%s\n' --max-heap $(UEFI_HEAP_MB) disk: --window-size $(UEFI_SCREEN) > $(UEFI)/esp/samaltak.args
	cp $(OVMF_VARS) $(UEFI)/vars.fd
	$(UEFI_WINDOW) $(QEMU_UEFI) $(UEFI_DISPLAY) $(if $(filter x86_64,$(UEFI_ARCH)),-vga std) -device qemu-xhci -device usb-kbd -device virtio-tablet-pci -serial stdio
uefi-control: uefi
	printf '%s\n' --max-heap $(UEFI_HEAP_MB) disk: --control --control-host 0.0.0.0 --control-port 7341 $(UEFI_CONTROL_ARGS) > $(UEFI)/esp/samaltak.args
	cp $(OVMF_VARS) $(UEFI)/vars.fd
	$(QEMU_UEFI) -display none $(if $(filter x86_64,$(UEFI_ARCH)),-vga std) -device qemu-xhci -device usb-kbd -device virtio-tablet-pci -serial stdio
UEFI_TESTS := CompilerTest ParserTest ScannerTest ClassTest CollectionTest ContextTest ExceptionTest FloatTest FractionTest \
	HashingTest ImmutabilityTest IntegerTest LazyContextTest MarriedContextTest MessageNotUnderstoodTest ObjectTest ProcessTest \
	StackOverflowTest StreamTest StringSearchTest StringTest SymbolTest SystemChangesTest SystemTest UnicodeTest WorkClockTest \
	Amd64DisassemblerTest Arm64DisassemblerTest ByteSearchTest
UEFI_WORLD := | w t | w := UIWindows startUp. RemoteInputDevice default inject: {1. nil. 123. 45. 0. 0. nil. w displayWindow windowId}. t := Time millisecondClockValue. [w dispatcher pointer = (123 @ 45) or: [Time millisecondClockValue - t > 20000]] whileFalse: [(Delay forMilliseconds: 50) wait]. Smalltalk vm stderrWrite: 'world ', w extent printString, ' ', Renderer default device isSoftware printString, ' ', w dispatcher pointer rounded printString, (String with: Character lf)
UEFI_NET := | s buf n | s := RemoteSocket connectTo: '10.0.2.2' port: $$P timeout: 20000. s sendAll: '{\"cmd\": \"ping\"}', (String with: Character lf). buf := ByteArray new: 200. n := s receiveInto: buf timeout: 20000. s close. (buf copyFrom: 1 to: n) asString
UEFI_NET_BULK := | src req s buf n chunk out t ms resp ok more | src := String new: 1000000. 1 to: src size do: [:i | src at: i put: (Character value: 97 + (i * 7 rem: 26))]. req := '{\"cmd\": \"eval\", \"source\": \"''', src, ''' reverse\"}', (String with: Character lf). t := Time millisecondClockValue. s := RemoteSocket connectTo: '10.0.2.2' port: $$P timeout: 20000. s sendAll: req. out := WriteStream on: (String new: 1100000). buf := ByteArray new: 65536. more := true. [more] whileTrue: [n := s receiveInto: buf timeout: 60000. chunk := (buf copyFrom: 1 to: n) asString. out nextPutAll: chunk. more := n > 0 and: [(chunk includes: Character lf) not]]. ms := Time millisecondClockValue - t. s close. resp := out contents. ok := (resp includesSubstring: '\"ok\":true') and: [resp includesSubstring: src reverse]. 'bulk ', ok printString, ' ', (req size + resp size) printString, ' bytes in ', ms printString, ' ms'
UEFI_NET_DRIVER := 'driver ', NetworkStack active interface class name
UEFI_DRIVER = $(if $(filter e1000e,$(1)),E1000eInterface,VirtioNetInterface)
UEFI_SNAPSHOT := Smalltalk at: 'UefiMark' asSymbol put: 42. (Smalltalk snapshot: Smalltalk vm imagePath) ifTrue: ['resumed ', (Smalltalk at: 'UefiMark' asSymbol) printString] ifFalse: ['saved']
test-uefi:
	rm -f $(UEFI)/image.disk
	$(MAKE) uefi-run UEFI_ARGS='--headless --test $(UEFI_TESTS)'
	$(MAKE) uefi-boot UEFI_ARGS="--eval \"$(UEFI_WORLD)\""
	grep -qE "^world [0-9]+@[0-9]+ true 123@45" $(UEFI)/console.log
	OUT=$(OUT) tools/samaltak-ctl --session uefi-test open --uefi --headless
	P=$$(sed -n 's/.*"port": \([0-9]*\).*/\1/p' $${TMPDIR:-/tmp}/samaltak-ctl/uefi-test.json); \
	tools/samaltak-ctl --session uefi-test eval "$(UEFI_NET_DRIVER)" > $(UEFI)/net.log; ok=$$?; \
	[ $$ok = 0 ] && { tools/samaltak-ctl --session uefi-test eval "$(UEFI_NET)" >> $(UEFI)/net.log; ok=$$?; }; \
	[ $$ok = 0 ] && { tools/samaltak-ctl --session uefi-test eval "$(UEFI_NET_BULK)" >> $(UEFI)/net.log; ok=$$?; }; \
	tools/samaltak-ctl --session uefi-test close; cat $(UEFI)/net.log; [ $$ok = 0 ] && grep -q pong $(UEFI)/net.log && grep -q "'bulk true" $(UEFI)/net.log \
		&& grep -q "'driver $(call UEFI_DRIVER,$(UEFI_NIC))'" $(UEFI)/net.log
	$(if $(filter-out virtio-net-pci,$(UEFI_NIC)),$(MAKE) test-uefi-nic UEFI_NIC=virtio-net-pci)
	$(MAKE) uefi-boot UEFI_ARGS="--headless --eval \"$(UEFI_SNAPSHOT)\""
	grep -q "'saved'" $(UEFI)/console.log
	$(MAKE) uefi-boot UEFI_ARGS=--headless
	grep -q "'resumed 42'" $(UEFI)/console.log
	rm $(UEFI)/image.disk
test-uefi-nic:
	UEFI_NIC=$(UEFI_NIC) OUT=$(OUT) tools/samaltak-ctl --session uefi-test open --uefi --headless
	P=$$(sed -n 's/.*"port": \([0-9]*\).*/\1/p' $${TMPDIR:-/tmp}/samaltak-ctl/uefi-test.json); \
	tools/samaltak-ctl --session uefi-test eval "$(UEFI_NET_DRIVER)" > $(UEFI)/net.log; ok=$$?; \
	[ $$ok = 0 ] && { tools/samaltak-ctl --session uefi-test eval "$(UEFI_NET)" >> $(UEFI)/net.log; ok=$$?; }; \
	tools/samaltak-ctl --session uefi-test close; cat $(UEFI)/net.log; [ $$ok = 0 ] && grep -q pong $(UEFI)/net.log \
		&& grep -q "'driver $(call UEFI_DRIVER,$(UEFI_NIC))'" $(UEFI)/net.log

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
	rm -rf build

.PHONY: all vm seed image fresh-image run translate uefi uefi-run uefi-boot uefi-ui uefi-control test-uefi test-uefi-nic test-vm test-jit test-jit-none test-jit-baseline test-jit-opt test-jit-deopt test-jit-cache test-core test-c4 test-c4-live test-tools test video mindblown-video jit-video clean
