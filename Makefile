# blueyos-bash — GNU Bash v5, GNU Readline 8.2, ncurses 6.5 for BlueyOS
# "Bingo!" - Bingo, Season 1
#
# Targets:
#   make              - build all packages (ncurses → readline → bash)
#   make ncurses      - build ncurses 6.5 and stage its dimsim payload
#   make readline     - build readline 8.2 and stage its dimsim payload
#   make bash         - build bash 5.2.21 and stage its dimsim payload
#   make dpk          - assemble .dpk archives with dpkbuild
#   make musl         - clone nzmacgeek/musl-blueyos and build for i386
#   make clean        - remove build artefacts
#   make help         - display this message
#
# Variables (override on command line):
#   MUSL_PREFIX       - path to a musl-blueyos sysroot.
#                       Defaults to /opt/blueyos-sysroot when present,
#                       otherwise falls back to build/musl.
#   BUILD_DIR         - output directory (default: build)
#   NCURSES_VERSION   - ncurses version to download  (default: 6.5)
#   READLINE_VERSION  - readline version to download (default: 8.2)
#   BASH_VERSION      - bash base version to download (default: 5.2)
#   BASH_PATCH_LEVEL  - number of official GNU bash patches to apply (default: 21)
#
# Quick start on a fresh host:
#   make musl            # build musl-blueyos sysroot into build/musl/
#   make                 # build all three packages
#   make dpk             # produce .dpk files
#
# Quick start on a BlueyOS build host (sysroot at /opt/blueyos-sysroot):
#   make                 # MUSL_PREFIX auto-resolves to /opt/blueyos-sysroot
#   make dpk
#
# ⚠️  VIBE CODED RESEARCH PROJECT — NOT FOR PRODUCTION USE ⚠️

# ---------------------------------------------------------------------------
# Package versions
# ---------------------------------------------------------------------------
NCURSES_VERSION  ?= 6.5
READLINE_VERSION ?= 8.2
BASH_VERSION     ?= 5.2
BASH_PATCH_LEVEL ?= 21

# ---------------------------------------------------------------------------
# Directories and sysroot
# ---------------------------------------------------------------------------
BUILD_DIR ?= build

BLUEYOS_SYSROOT ?= /opt/blueyos-sysroot
ifeq ($(shell [ -d $(BLUEYOS_SYSROOT) ] && echo yes),yes)
  MUSL_PREFIX ?= $(BLUEYOS_SYSROOT)
else
  MUSL_PREFIX ?= $(BUILD_DIR)/musl
endif

# Build-time install prefixes used as inputs for the next package in the chain.
NCURSES_PREFIX  := $(BUILD_DIR)/ncurses-install
READLINE_PREFIX := $(BUILD_DIR)/readline-install

# Compiler: prefer the musl-gcc wrapper produced by `make musl`.
# This avoids accidentally mixing glibc start files with musl headers.
# Override on the command line if you have a dedicated cross-compiler:
#   make CC=i386-linux-musl-gcc
MUSL_GCC := $(MUSL_PREFIX)/bin/musl-gcc
ifeq ($(shell [ -x $(MUSL_GCC) ] && echo yes),yes)
  CC ?= $(MUSL_GCC)
else
  CC ?= gcc
endif

# ---------------------------------------------------------------------------
# Phony targets
# ---------------------------------------------------------------------------
.PHONY: all ncurses readline bash dpk musl musl-check clean help

.DEFAULT_GOAL := all

# ---------------------------------------------------------------------------
# all — build the full chain
# ---------------------------------------------------------------------------
all: bash

# ---------------------------------------------------------------------------
# musl — clone and build musl-blueyos for i386
# ---------------------------------------------------------------------------
musl:
	@bash tools/build-musl.sh --prefix=$(MUSL_PREFIX)

# ---------------------------------------------------------------------------
# musl-check — abort early if the sysroot is missing
# ---------------------------------------------------------------------------
define check_musl
	@if [ ! -d "$(MUSL_PREFIX)/include" ] || [ ! -f "$(MUSL_PREFIX)/lib/libc.a" ]; then \
		echo ""; \
		echo "  [MUSL] musl sysroot not found under $(MUSL_PREFIX)"; \
		echo "         Run:  make musl   (or)  make MUSL_PREFIX=/path/to/sysroot"; \
		echo ""; \
		exit 1; \
	fi
endef

musl-check:
	$(call check_musl)

# ---------------------------------------------------------------------------
# ncurses — download + cross-compile + stage payload
# ---------------------------------------------------------------------------
ncurses: musl-check
	@NCURSES_VERSION=$(NCURSES_VERSION) \
	  MUSL_PREFIX=$(MUSL_PREFIX) \
	  BUILD_DIR=$(BUILD_DIR) \
	  INSTALL_PREFIX=$(NCURSES_PREFIX) \
	  STAGE_DIR=$(CURDIR)/ncurses/payload \
	  CC=$(CC) \
	  bash tools/build-ncurses.sh
	@echo ""
	@echo "  [OK]  ncurses $(NCURSES_VERSION) — payload staged in ncurses/payload/"

# ---------------------------------------------------------------------------
# readline — depends on ncurses
# ---------------------------------------------------------------------------
readline: ncurses
	@READLINE_VERSION=$(READLINE_VERSION) \
	  MUSL_PREFIX=$(MUSL_PREFIX) \
	  BUILD_DIR=$(BUILD_DIR) \
	  NCURSES_PREFIX=$(NCURSES_PREFIX) \
	  INSTALL_PREFIX=$(READLINE_PREFIX) \
	  STAGE_DIR=$(CURDIR)/readline/payload \
	  CC=$(CC) \
	  bash tools/build-readline.sh
	@echo ""
	@echo "  [OK]  readline $(READLINE_VERSION) — payload staged in readline/payload/"

# ---------------------------------------------------------------------------
# bash — depends on ncurses and readline
# ---------------------------------------------------------------------------
bash: readline
	@BASH_VERSION=$(BASH_VERSION) \
	  BASH_PATCH_LEVEL=$(BASH_PATCH_LEVEL) \
	  MUSL_PREFIX=$(MUSL_PREFIX) \
	  BUILD_DIR=$(BUILD_DIR) \
	  NCURSES_PREFIX=$(NCURSES_PREFIX) \
	  READLINE_PREFIX=$(READLINE_PREFIX) \
	  STAGE_DIR=$(CURDIR)/bash/payload \
	  CC=$(CC) \
	  bash tools/build-bash.sh
	@echo ""
	@echo "  [OK]  bash $(BASH_VERSION).$(BASH_PATCH_LEVEL) — payload staged in bash/payload/"

# ---------------------------------------------------------------------------
# dpk — assemble .dpk packages from the staged payloads
#        Requires dpkbuild on PATH (from nzmacgeek/dimsim).
# ---------------------------------------------------------------------------
dpk:
	@command -v dpkbuild >/dev/null 2>&1 || { \
		echo "  [DPK] dpkbuild not found on PATH."; \
		echo "        Build it from https://github.com/nzmacgeek/dimsim"; \
		exit 1; \
	}
	@mkdir -p $(BUILD_DIR)/dpk
	dpkbuild build ncurses/   --output $(BUILD_DIR)/dpk
	dpkbuild build readline/  --output $(BUILD_DIR)/dpk
	dpkbuild build bash/      --output $(BUILD_DIR)/dpk
	@echo ""
	@echo "  .dpk files written to $(BUILD_DIR)/dpk/"
	@ls -1 $(BUILD_DIR)/dpk/*.dpk

# ---------------------------------------------------------------------------
# clean
# ---------------------------------------------------------------------------
clean:
	@if [ -z "$(BUILD_DIR)" ] || [ "$(BUILD_DIR)" = "/" ] || [ "$(BUILD_DIR)" = "." ]; then \
		echo "  [CLEAN] Refusing to remove unsafe BUILD_DIR='$(BUILD_DIR)'"; exit 1; \
	fi
	rm -rf -- "$(BUILD_DIR)"
	@echo "  [CLEAN] Build artefacts removed from $(BUILD_DIR)/."

# ---------------------------------------------------------------------------
# help
# ---------------------------------------------------------------------------
help:
	@echo "blueyos-bash — GNU Bash v5 + Readline + ncurses for BlueyOS"
	@echo ""
	@echo "  make              build ncurses → readline → bash (default)"
	@echo "  make musl         clone musl-blueyos and build for i386"
	@echo "  make ncurses      build ncurses $(NCURSES_VERSION) only"
	@echo "  make readline     build readline $(READLINE_VERSION) only"
	@echo "  make bash         build bash $(BASH_VERSION).$(BASH_PATCH_LEVEL) only"
	@echo "  make dpk          assemble .dpk packages (requires dpkbuild)"
	@echo "  make clean        remove build artefacts"
	@echo ""
	@echo "Variables:"
	@echo "  MUSL_PREFIX=...        musl sysroot  (default: $(MUSL_PREFIX))"
	@echo "  CC=...                 C compiler    (default: $(CC))"
	@echo "  BUILD_DIR=...          output dir    (default: build)"
	@echo "  NCURSES_VERSION=...    (default: $(NCURSES_VERSION))"
	@echo "  READLINE_VERSION=...   (default: $(READLINE_VERSION))"
	@echo "  BASH_VERSION=...       (default: $(BASH_VERSION))"
	@echo "  BASH_PATCH_LEVEL=...   (default: $(BASH_PATCH_LEVEL))"
	@echo ""
	@echo "Example:"
	@echo "  make MUSL_PREFIX=/opt/blueyos-sysroot"
