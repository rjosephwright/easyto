PROJECT := $(shell basename ${PWD})
OS := $(shell uname | tr [:upper:] [:lower:])
ARCH := $(shell arch=$$(uname -m); [ "$${arch}" = "x86_64" ] && echo "amd64" || echo $${arch})
VERSION :=

DIR_ROOT := $(shell echo ${PWD})
DIR_OUT := $(DIR_ROOT)/_output
DIR_CB := __cb__
DIR_OUT_CB := $(DIR_ROOT)/_output/$(DIR_CB)
DIR_BOOTLOADER := $(DIR_OUT)/bootloader
DIR_PREINIT := $(DIR_OUT)/preinit
DIR_KERNEL := $(DIR_OUT)/kernel
DIR_RELEASE := $(DIR_OUT)/release/$(OS)/$(ARCH)
DIR_RELEASE_ASSETS := $(DIR_RELEASE)/assets
DIR_RELEASE_BIN := $(DIR_RELEASE)/bin
DIR_RELEASE_PACKER := $(DIR_RELEASE)/packer
DIR_RELEASE_PACKER_PLUGIN := $(DIR_RELEASE_PACKER)/plugins/github.com/hashicorp/amazon
DIR_OSARCH_BUILD := $(DIR_OUT)/osarch/$(OS)/$(ARCH)

COMMIT_ID_HEAD := $(shell git rev-parse HEAD)
CTR_IMAGE_GO := golang:1.21.0-alpine3.18
CTR_IMAGE_LOCAL := $(PROJECT):$(COMMIT_ID_HEAD)

KERNEL_ORG := https://cdn.kernel.org/pub/linux

E2FSPROGS_VERSION := 1.47.0
E2FSPROGS_SRC := e2fsprogs-$(E2FSPROGS_VERSION)
E2FSPROGS_ARCHIVE := $(E2FSPROGS_SRC).tar.gz
E2FSPROGS_URL := $(KERNEL_ORG)/kernel/people/tytso/e2fsprogs/v$(E2FSPROGS_VERSION)/$(E2FSPROGS_ARCHIVE)

KERNEL_VERSION := 6.1.52
KERNEL_VERSION_MAJ := $(shell echo $(KERNEL_VERSION) | cut -c 1)
KERNEL_SRC := linux-$(KERNEL_VERSION)
KERNEL_ARCHIVE := $(KERNEL_SRC).tar.xz
KERNEL_URL := $(KERNEL_ORG)/kernel/v$(KERNEL_VERSION_MAJ).x/$(KERNEL_ARCHIVE)

PACKER_VERSION := 1.9.4
PACKER_ARCHIVE := packer_$(PACKER_VERSION)_$(OS)_$(ARCH).zip
PACKER_URL := https://releases.hashicorp.com/packer/$(PACKER_VERSION)/$(PACKER_ARCHIVE)

PACKER_PLUGIN_AMZ_VERSION := 1.2.6
PACKER_PLUGIN_AMZ_FILE := packer-plugin-amazon_v$(PACKER_PLUGIN_AMZ_VERSION)_x5.0_$(OS)_$(ARCH)
PACKER_PLUGIN_AMZ_ARCHIVE := $(PACKER_PLUGIN_AMZ_FILE).zip
PACKER_PLUGIN_AMZ_URL := https://github.com/hashicorp/packer-plugin-amazon/releases/download/v$(PACKER_PLUGIN_AMZ_VERSION)/$(PACKER_PLUGIN_AMZ_ARCHIVE)

SYSTEMD_BOOT_VERSION := 252.12-1~deb12u1
SYSTEMD_BOOT_ARCHIVE := systemd-boot-efi_$(SYSTEMD_BOOT_VERSION)_amd64.deb
SYSTEMD_BOOT_URL := https://ftp.debian.org/debian/pool/main/s/systemd/$(SYSTEMD_BOOT_ARCHIVE)

UTIL_LINUX_VERSION := 2.39
UTIL_LINUX_SRC := util-linux-$(UTIL_LINUX_VERSION)
UTIL_LINUX_ARCHIVE := $(UTIL_LINUX_SRC).tar.gz
UTIL_LINUX_URL := $(KERNEL_ORG)/utils/util-linux/v$(UTIL_LINUX_VERSION)/$(UTIL_LINUX_ARCHIVE)

HAS_COMMAND_AR := $(DIR_OUT)/.command-ar
HAS_COMMAND_CURL := $(DIR_OUT)/.command-curl
HAS_COMMAND_DOCKER := $(DIR_OUT)/.command-docker
HAS_COMMAND_FAKEROOT := $(DIR_OUT)/.command-fakeroot
HAS_COMMAND_UNZIP := $(DIR_OUT)/.command-unzip
HAS_COMMAND_XZCAT := $(DIR_OUT)/.command-xzcat
HAS_IMAGE_LOCAL := $(DIR_OUT)/.image-local-$(COMMIT_ID_HEAD)

default: release

bootloader: $(DIR_BOOTLOADER)/boot/EFI/BOOT/BOOTX64.EFI

blkid: $(DIR_PREINIT)/$(DIR_CB)/blkid

converter: $(DIR_OUT)/converter

e2fsprogs: $(DIR_PREINIT)/$(DIR_CB)/mke2fs $(DIR_PREINIT)/$(DIR_CB)/mkfs.ext2 \
	$(DIR_PREINIT)/$(DIR_CB)/mkfs.ext3 $(DIR_PREINIT)/$(DIR_CB)/mkfs.ext4

kernel: $(DIR_KERNEL)/boot/vmlinuz-$(KERNEL_VERSION)

preinit: $(DIR_PREINIT)/$(DIR_CB)/preinit

packer: $(DIR_RELEASE_PACKER)/build.pkr.hcl \
		$(DIR_RELEASE_PACKER)/packer \
		$(DIR_RELEASE_PACKER)/provision \
		$(DIR_RELEASE_PACKER_PLUGIN)/$(PACKER_PLUGIN_AMZ_FILE)_SHA256SUM

unpack: $(DIR_OSARCH_BUILD)/unpack

assets-bootloader: $(DIR_RELEASE_ASSETS)/boot.tar

assets-converter: $(DIR_RELEASE_ASSETS)/converter

assets-preinit: $(DIR_RELEASE_ASSETS)/preinit.tar

assets-kernel: $(DIR_RELEASE_ASSETS)/kernel-$(KERNEL_VERSION).tar

release-one: $(DIR_RELEASE)/unpack-$(VERSION)-$(OS)-$(ARCH).tar.gz

release:
	for os in linux darwin; do \
		for arch in amd64 arm64; do \
			$(MAKE) $(DIR_OUT)/release/$${os}/$${arch}/unpack-$(VERSION)-$${os}-$${arch}.tar.gz \
				OS=$${os} ARCH=$${arch}; \
		done; \
	done

$(DIR_BOOTLOADER)/boot/EFI/BOOT/BOOTX64.EFI: $(HAS_COMMAND_AR) $(HAS_COMMAND_XZCAT) \
		$(DIR_OUT)/$(SYSTEMD_BOOT_ARCHIVE)
	@$(MAKE) $(DIR_BOOTLOADER)/tmp/ $(DIR_BOOTLOADER)/boot/EFI/BOOT/
	@ar --output $(DIR_BOOTLOADER)/tmp xf $(DIR_OUT)/$(SYSTEMD_BOOT_ARCHIVE) data.tar.xz
	@xzcat $(DIR_BOOTLOADER)/tmp/data.tar.xz | \
		tar -mxf - \
		--xform "s|.*/systemd-bootx64.efi|_output/bootloader/boot/EFI/BOOT/BOOTX64.EFI|" \
		./usr/lib/systemd/boot/efi/systemd-bootx64.efi

$(DIR_OUT)/$(SYSTEMD_BOOT_ARCHIVE): $(HAS_COMMAND_CURL)
	@curl -o $(DIR_OUT)/$(SYSTEMD_BOOT_ARCHIVE) $(SYSTEMD_BOOT_URL)

$(DIR_OUT)/$(E2FSPROGS_SRC)/misc/mke2fs: $(HAS_IMAGE_LOCAL) $(DIR_OUT)/$(E2FSPROGS_SRC)
	@docker run -it \
		-v $(DIR_OUT)/$(E2FSPROGS_SRC):/code \
		-e LDFLAGS="-s -static" \
		-w /code \
		$(CTR_IMAGE_LOCAL) /bin/sh -c "$$(cat $(DIR_ROOT)/hack/compile-e2fsprogs-ctr)"

$(DIR_OUT)/$(E2FSPROGS_SRC): $(DIR_OUT)/$(E2FSPROGS_ARCHIVE)
	@tar zxf $(DIR_OUT)/$(E2FSPROGS_ARCHIVE) -C $(DIR_OUT)

$(DIR_OUT)/$(E2FSPROGS_ARCHIVE): $(HAS_COMMAND_CURL)
	@curl -o $(DIR_OUT)/$(E2FSPROGS_ARCHIVE) $(E2FSPROGS_URL)

$(DIR_PREINIT)/$(DIR_CB)/mke2fs: $(DIR_OUT)/$(E2FSPROGS_SRC)/misc/mke2fs
	@$(MAKE) $(DIR_PREINIT)/$(DIR_CB)/
	@install -m 0755 $(DIR_OUT)/$(E2FSPROGS_SRC)/misc/mke2fs $(DIR_PREINIT)/$(DIR_CB)/mke2fs

$(DIR_PREINIT)/$(DIR_CB)/mkfs.ext%: $(DIR_PREINIT)/$(DIR_CB)/mke2fs
	@$(MAKE) $(DIR_PREINIT)/$(DIR_CB)/
	@ln -f $(DIR_PREINIT)/$(DIR_CB)/mke2fs $(DIR_PREINIT)/$(DIR_CB)/mkfs.ext$*

$(DIR_PREINIT)/$(DIR_CB)/preinit: $(HAS_IMAGE_LOCAL) \
		$(shell find preinit -type f -path '*.go' ! -path '*_test.go')
	@$(MAKE) $(DIR_PREINIT)/$(DIR_CB)/
	@docker run -it \
		-v $(DIR_ROOT):/code \
		-e DIR_OUT=/code/_output/preinit/$(DIR_CB) \
		-e GOPATH=/code/_output/go \
		-e GOCACHE=/code/_output/gocache \
		-e CGO_ENABLED=1 \
		-w /code/preinit \
		$(CTR_IMAGE_LOCAL) /bin/sh -c "$$(cat $(DIR_ROOT)/hack/compile-preinit-ctr)"

# Other files are created by the kernel build, but vmlinuz-$(KERNEL_VERSION) will
# be used to indicate the target is created. It is the last file created by the build
# via the $(DIR_ROOT)/kernel/installkernel script mounted in the build container.
$(DIR_KERNEL)/boot/vmlinuz-$(KERNEL_VERSION): $(HAS_IMAGE_LOCAL) $(DIR_OUT)/$(KERNEL_SRC) kernel/config
	@$(MAKE) $(DIR_KERNEL)/boot/ $(DIR_KERNEL)/$(DIR_CB)/
	@docker run -it \
		-v $(DIR_OUT)/$(KERNEL_SRC):/code \
		-v $(DIR_KERNEL):/install \
		-v $(DIR_ROOT)/kernel/config:/config \
		-v $(DIR_ROOT)/kernel/installkernel:/sbin/installkernel \
		-e INSTALL_PATH=/install/boot \
		-e INSTALL_MOD_PATH=/install/$(DIR_CB) \
		-w /code \
		$(CTR_IMAGE_LOCAL) /bin/sh -c "$$(cat $(DIR_ROOT)/hack/compile-kernel-ctr)"
	@rm -f $(DIR_KERNEL)/$(DIR_CB)/lib/modules/$(KERNEL_VERSION)/build
	@rm -f $(DIR_KERNEL)/$(DIR_CB)/lib/modules/$(KERNEL_VERSION)/source

$(DIR_OUT)/$(KERNEL_SRC): $(HAS_COMMAND_XZCAT) $(DIR_OUT)/$(KERNEL_ARCHIVE)
	@xzcat $(DIR_OUT)/$(KERNEL_ARCHIVE) | tar xf - -C $(DIR_OUT)

$(DIR_OUT)/$(KERNEL_ARCHIVE): $(HAS_COMMAND_CURL)
	@curl -o $(DIR_OUT)/$(KERNEL_ARCHIVE) $(KERNEL_URL)

$(DIR_PREINIT)/$(DIR_CB)/amazon.pem: amazon.pem
	@$(MAKE) $(DIR_PREINIT)/$(DIR_CB)/
	@install -m 0644 amazon.pem $(DIR_PREINIT)/$(DIR_CB)/amazon.pem

$(DIR_PREINIT)/$(DIR_CB)/blkid: $(DIR_OUT)/$(UTIL_LINUX_SRC)/blkid.static
	@$(MAKE) $(DIR_PREINIT)/$(DIR_CB)/
	@install -m 0755 $(DIR_OUT)/$(UTIL_LINUX_SRC)/blkid.static $(DIR_PREINIT)/$(DIR_CB)/blkid

$(DIR_OUT)/$(UTIL_LINUX_SRC)/blkid.static: $(HAS_IMAGE_LOCAL) $(DIR_OUT)/$(UTIL_LINUX_SRC)
	@docker run -it \
		-v $(DIR_ROOT)/_output/$(UTIL_LINUX_SRC):/code \
		-e CFLAGS=-s \
		-w /code \
		$(CTR_IMAGE_LOCAL) /bin/sh -c "$$(cat $(DIR_ROOT)/hack/compile-blkid-ctr)"

# Container image build is done in an empty directory to speed it up.
$(HAS_IMAGE_LOCAL): $(HAS_COMMAND_DOCKER)
	@$(MAKE) $(DIR_OUT)/dockerbuild/
	@docker build --build-arg FROM=$(CTR_IMAGE_GO) \
		--build-arg GID=$$(id -g) \
		--build-arg UID=$$(id -u) \
		-f $(DIR_ROOT)/Dockerfile.build \
		-t $(CTR_IMAGE_LOCAL) \
		$(DIR_OUT)/dockerbuild
	@touch $(HAS_IMAGE_LOCAL)

$(DIR_OUT)/$(UTIL_LINUX_SRC): $(DIR_OUT)/$(UTIL_LINUX_ARCHIVE)
	@tar zxf $(DIR_OUT)/$(UTIL_LINUX_ARCHIVE) -C $(DIR_OUT)

$(DIR_OUT)/$(UTIL_LINUX_ARCHIVE): $(HAS_COMMAND_CURL)
	@curl -o $(DIR_OUT)/$(UTIL_LINUX_ARCHIVE) $(UTIL_LINUX_URL)

$(DIR_RELEASE_ASSETS)/boot.tar: $(HAS_COMMAND_FAKEROOT) $(DIR_BOOTLOADER)/boot/EFI/BOOT/BOOTX64.EFI
	@$(MAKE) $(DIR_RELEASE_ASSETS)/ $(DIR_BOOTLOADER)/boot/loader/entries/
	@chmod -R 0755 $(DIR_BOOTLOADER)
	@cd $(DIR_BOOTLOADER) && fakeroot tar cf $(DIR_RELEASE_ASSETS)/boot.tar boot

$(DIR_RELEASE_ASSETS)/converter: $(DIR_OUT)/converter
	@$(MAKE) $(DIR_RELEASE_ASSETS)/
	@install -m 0755 $(DIR_OUT)/converter $(DIR_RELEASE_ASSETS)/converter

$(DIR_OUT)/converter: $(HAS_IMAGE_LOCAL) \
		$(shell find ctr2ami -type f -path '*.go' ! -path '*_test.go')
	@docker run -it \
		-v $(DIR_ROOT):/code \
		-e DIR_OUT=/code/_output \
		-e GOPATH=/code/_output/go \
		-e GOCACHE=/code/_output/gocache \
		-e CGO_ENABLED=0 \
		-w /code/ctr2ami \
		$(CTR_IMAGE_LOCAL) /bin/sh -c "$$(cat $(DIR_ROOT)/hack/compile-converter-ctr)"

$(DIR_RELEASE_ASSETS)/kernel-$(KERNEL_VERSION).tar: $(HAS_COMMAND_FAKEROOT) \
		$(DIR_KERNEL)/boot/vmlinuz-$(KERNEL_VERSION)
	@$(MAKE) $(DIR_RELEASE_ASSETS)/
	@cd $(DIR_KERNEL) && fakeroot tar cf $(DIR_RELEASE_ASSETS)/kernel-$(KERNEL_VERSION).tar .

$(DIR_RELEASE_ASSETS)/preinit.tar: \
		$(HAS_COMMAND_FAKEROOT) \
		$(DIR_PREINIT)/$(DIR_CB)/amazon.pem \
		$(DIR_PREINIT)/$(DIR_CB)/blkid \
		$(DIR_PREINIT)/$(DIR_CB)/mke2fs \
		$(DIR_PREINIT)/$(DIR_CB)/mkfs.ext2 \
		$(DIR_PREINIT)/$(DIR_CB)/mkfs.ext3 \
		$(DIR_PREINIT)/$(DIR_CB)/mkfs.ext4 \
		$(DIR_PREINIT)/$(DIR_CB)/preinit
	@$(MAKE) $(DIR_RELEASE_ASSETS)/
	@cd $(DIR_PREINIT) && fakeroot tar cf $(DIR_RELEASE_ASSETS)/preinit.tar .

$(DIR_RELEASE)/unpack-$(VERSION)-$(OS)-$(ARCH).tar.gz: $(HAS_COMMAND_FAKEROOT) packer \
		$(DIR_RELEASE_ASSETS)/boot.tar \
		$(DIR_RELEASE_ASSETS)/converter \
		$(DIR_RELEASE_ASSETS)/preinit.tar \
		$(DIR_RELEASE_ASSETS)/kernel-$(KERNEL_VERSION).tar \
		$(DIR_RELEASE_BIN)/unpack
	@[ -n "$(VERSION)" ] || (echo "VERSION is required"; exit 1)
	@cd $(DIR_RELEASE) && \
		fakeroot tar czf $(DIR_RELEASE)/unpack-$(VERSION)-$(OS)-$(ARCH).tar.gz assets bin packer

$(DIR_RELEASE_BIN)/unpack: $(DIR_OSARCH_BUILD)/unpack
	@$(MAKE) $(DIR_RELEASE_BIN)/
	@install -m 0755 $(DIR_OSARCH_BUILD)/unpack $(DIR_RELEASE_BIN)/unpack

$(DIR_OSARCH_BUILD)/unpack: $(HAS_IMAGE_LOCAL) \
		$(shell find unpack -type f -path '*.go' ! -path '*_test.go')
	@[ -d $(DIR_OSARCH_BUILD) ] || mkdir -p $(DIR_OSARCH_BUILD)
	@docker run -it \
		-v $(DIR_ROOT):/code \
		-e DIR_OUT=/code/_output/osarch/$(OS)/$(ARCH) \
		-e GOPATH=/code/_output/go \
		-e GOCACHE=/code/_output/gocache \
		-e CGO_ENABLED=0 \
		-e GOARCH=$(ARCH) \
		-e GOOS=$(OS) \
		-e KERNEL_VERSION=$(KERNEL_VERSION) \
		-w /code/unpack \
		$(CTR_IMAGE_LOCAL) /bin/sh -c "$$(cat $(DIR_ROOT)/hack/compile-unpack-ctr)"

$(DIR_RELEASE_PACKER)/packer: $(HAS_COMMAND_UNZIP) $(DIR_OUT)/$(PACKER_ARCHIVE)
	@$(MAKE) $(DIR_RELEASE_PACKER)/
	@unzip -o $(DIR_OUT)/$(PACKER_ARCHIVE) -d $(DIR_RELEASE_PACKER)
	@touch $(DIR_RELEASE_PACKER)/packer

$(DIR_OUT)/$(PACKER_ARCHIVE): $(HAS_COMMAND_CURL)
	@curl -o $(DIR_OUT)/$(PACKER_ARCHIVE) $(PACKER_URL)

$(DIR_RELEASE_PACKER)/build.pkr.hcl: $(DIR_ROOT)/packer/build.pkr.hcl
	@$(MAKE) $(DIR_RELEASE_PACKER)/
	@install -m 0644 $(DIR_ROOT)/packer/build.pkr.hcl $(DIR_RELEASE_PACKER)/build.pkr.hcl

$(DIR_RELEASE_PACKER)/provision: $(DIR_ROOT)/packer/provision
	@install -m 0755 $(DIR_ROOT)/packer/provision $(DIR_RELEASE_PACKER)/provision

$(DIR_RELEASE_PACKER_PLUGIN)/$(PACKER_PLUGIN_AMZ_FILE)_SHA256SUM: $(DIR_RELEASE_PACKER_PLUGIN)/$(PACKER_PLUGIN_AMZ_FILE)
	@sha256sum $(DIR_RELEASE_PACKER_PLUGIN)/$(PACKER_PLUGIN_AMZ_FILE) | \
		awk '{print $1}' > $(DIR_RELEASE_PACKER_PLUGIN)/$(PACKER_PLUGIN_AMZ_FILE)_SHA256SUM

$(DIR_RELEASE_PACKER_PLUGIN)/$(PACKER_PLUGIN_AMZ_FILE): $(HAS_COMMAND_UNZIP) \
		$(DIR_OUT)/$(PACKER_PLUGIN_AMZ_ARCHIVE)
	@$(MAKE) $(DIR_RELEASE_PACKER_PLUGIN)/
	@unzip -o $(DIR_OUT)/$(PACKER_PLUGIN_AMZ_ARCHIVE) -d $(DIR_RELEASE_PACKER_PLUGIN)
	@touch $(DIR_RELEASE_PACKER_PLUGIN)/$(PACKER_PLUGIN_AMZ_FILE)

$(DIR_OUT)/$(PACKER_PLUGIN_AMZ_ARCHIVE): $(HAS_COMMAND_CURL)
	@curl -L -o $(DIR_OUT)/$(PACKER_PLUGIN_AMZ_ARCHIVE) $(PACKER_PLUGIN_AMZ_URL)

# Create empty file `_output/.command-abc` if command `abc` is found.
$(DIR_OUT)/.command-%:
	@[ -d $(DIR_OUT) ] || mkdir -p $(DIR_OUT)
	@which $* 2>&1 >/dev/null && touch $(DIR_OUT)/.command-$* || (echo "$* is required"; exit 1)

# Create any directory under $(DIR_OUT) as long as it ends in a `/` character.
$(DIR_OUT)/%/:
	@[ -d $(DIR_OUT)/$* ] || mkdir -p $(DIR_OUT)/$*

clean-converter:
	@rm -f $(DIR_OUT)/converter

clean-blkid:
	@rm -f $(DIR_OUT)/$(UTIL_LINUX_ARCHIVE)
	@rm -f $(DIR_PREINIT)/$(DIR_CB)/blkid
	@rm -rf $(DIR_OUT)/$(UTIL_LINUX_SRC)

	@rm -f $(DIR_PREINIT)/$(DIR_CB)/blkid
	@rm -f $(DIR_OUT)/$(UTIL_LINUX_ARCHIVE)
	@rm -rf $(DIR_OUT)/$(UTIL_LINUX_SRC)

clean-e2fsprogs:
	@rm -f $(DIR_OUT)/$(E2FSPROGS_ARCHIVE)
	@rm -f $(DIR_PREINIT)/$(DIR_CB)/mke2fs $(DIR_PREINIT)/$(DIR_CB)/mkfs.ext*
	@rm -rf $(DIR_OUT)/$(E2FSPROGS_SRC)

clean-kernel:
	@rm -f $(DIR_OUT)/$(KERNEL_ARCHIVE)
	@rm -rf $(DIR_OUT)/$(KERNEL_SRC)
	@rm -rf $(DIR_OUT)/kernel

clean-preinit:
	@rm -f $(DIR_PREINIT)/$(DIR_CB)/preinit

clean:
	@chmod -R +w $(DIR_OUT)/go
	@rm -rf $(DIR_OUT)
