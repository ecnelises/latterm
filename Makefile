ORIG_PATH := $(PATH)
PATH := /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
APP_NAME = Latterm
APP_BUNDLE = $(APP_NAME).app
APP_EXECUTABLE = $(APP_NAME)
ITERM_PID=$(shell pgrep "$(APP_EXECUTABLE)")
APPS := /Applications
ITERM_CONF_PLIST = $(HOME)/Library/Preferences/com.googlecode.iterm2.plist
# Release uses Latterm as its Application Support directory. Keep dev data separate.
SUITE ?= $(notdir $(CURDIR))-Development
VERSION = $(shell cat version.txt)
NAME=$(shell echo $(VERSION) | sed -e "s/\\./_/g")
HOMEBREW_PREFIX ?= $(shell brew --prefix 2>/dev/null || echo /opt/homebrew)
DEPLOYMENT_TARGET=15.0
XCODEBUILD_ITERM = xcodebuild -project iTerm2.xcodeproj -scheme iTerm2

# Build products live in a repo-local directory by default so make does not
# depend on Xcode's derived settings or user cache directories.
BUILD_DIR ?= $(CURDIR)/Build
RUN_DIR = $(BUILD_DIR)/$(SUITE)
DERIVED_DATA_DIR ?= $(BUILD_DIR)/DerivedData
BUILD_HOME ?= $(BUILD_DIR)/Home
_NEEDS_BUILD_DIR := $(if $(filter-out setup dangerous-setup _setup-main help doctor,$(MAKECMDGOALS)),yes,$(if $(MAKECMDGOALS),,yes))
ifdef _NEEDS_BUILD_DIR
  ifeq ($(strip $(BUILD_DIR)),)
    $(error BUILD_DIR is empty. Set BUILD_DIR=/path/to/dir to override.)
  endif
  ifeq ($(patsubst /%,%,$(BUILD_DIR)),$(BUILD_DIR))
    $(error BUILD_DIR is not an absolute path: $(BUILD_DIR))
  endif
  ifneq ($(shell d='$(BUILD_DIR)'; while [ ! -d "$$d" ]; do d=$$(dirname "$$d"); done; [ -w "$$d" ] && echo ok),ok)
    $(error BUILD_DIR is not writable: $(BUILD_DIR))
  endif
endif

# Code signing: disabled by default (contributor-friendly).
# Use SIGNED=1 to build with the project's signing identity.
ifndef SIGNED
  SIGNING_FLAGS = CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
endif

# Latterm targets Apple Silicon only.
TARGET_ARCH := arm64
ARCH_FLAGS = ARCHS="$(TARGET_ARCH)" ONLY_ACTIVE_ARCH=YES

.PHONY: clean all backup-old-iterm restart setup dangerous-setup _setup-main help doctor

help:
	@echo "$(APP_NAME) — $(VERSION) ($(TARGET_ARCH))"
	@echo ""
	@echo "First time:"
	@echo "  make setup            Install all build dependencies (interactive)"
	@echo "  make dangerous-setup  Same as setup, skip all confirmations"
	@echo ""
	@echo "Build:"
	@echo "  make              Build Development (default)"
	@echo "  make dev          Build Development"
	@echo "  make prod         Build Deployment"
	@echo "  make run          Build and launch Development build"
	@echo "  make watch        Build and launch with interactive r=reload q=quit loop"
	@echo "  make test         Run ModernTests unit tests"
	@echo "  make install      Build Deployment and install to /Applications"
	@echo ""
	@echo "Dependencies:"
	@echo "  make paranoid-deps  Rebuild bundled native dependencies (sandboxed)"
	@echo "  make DepsIfNeeded   Rebuild deps only if Xcode version changed"
	@echo "  make clean        Remove build products"
	@echo "  make cleandeps    Clean dependency build directories"
	@echo ""
	@echo "Release:"
	@echo "  make Beta         Build Beta configuration"
	@echo "  make Nightly      Build Nightly configuration"
	@echo "  make Deployment   Build Deployment configuration"
	@echo "  tools/release_latterm.sh VERSION"
	@echo "                     Sign, notarize, and package a release"
	@echo ""
	@echo "Diagnose:"
	@echo "  make doctor       Check all build dependencies"
	@echo ""
	@echo "Options:"
	@echo "  SIGNED=1          Enable code signing"
	@echo "  BUILD_DIR=/path   Override build output directory"
	@echo ""
	@echo "Homebrew: $(HOMEBREW_PREFIX)"

all: Development
dev: Development
prod: Deployment

setup:
	@BREW_BIN=$$(PATH="/opt/homebrew/bin:/usr/local/bin:$(ORIG_PATH)" command -v brew 2>/dev/null); \
	if [ -z "$$BREW_BIN" ]; then \
		echo "Homebrew is not installed."; \
		if [ "$(SKIP_CONFIRM)" != "1" ]; then \
			printf "Install Homebrew via its official install script (requires sudo)? [y/N] "; \
			read ans </dev/tty; case "$$ans" in [yY]) ;; *) echo "Aborted."; exit 1;; esac; \
		fi; \
		NONINTERACTIVE=1 /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; \
		BREW_BIN=$$(command -v /opt/homebrew/bin/brew 2>/dev/null || command -v /usr/local/bin/brew 2>/dev/null); \
		if [ -z "$$BREW_BIN" ]; then \
			echo "Error: Homebrew installation failed."; \
			exit 1; \
		fi; \
	fi; \
	if ! PATH="$(ORIG_PATH)" command -v brew >/dev/null 2>&1; then \
		echo "Restarting setup with Homebrew in PATH..."; \
		PATH="$$(dirname $$BREW_BIN):$(ORIG_PATH)" \
			$(MAKE) _setup-main SKIP_CONFIRM="$(SKIP_CONFIRM)"; \
	else \
		$(MAKE) _setup-main SKIP_CONFIRM="$(SKIP_CONFIRM)"; \
	fi

dangerous-setup:
	@$(MAKE) setup SKIP_CONFIRM=1

_setup-main:
	@XCODE_DEV=$$(PATH="$(ORIG_PATH)" xcode-select -p 2>/dev/null); \
	if echo "$$XCODE_DEV" | grep -q '/Xcode.*\.app'; then \
		XCODE_APP=$$(echo "$$XCODE_DEV" | sed 's|/Contents/Developer.*||'); \
		echo "Xcode already selected: $$XCODE_APP"; \
	else \
		echo "Xcode.app is not selected."; \
		XCODE_APP=$$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1); \
		if [ -n "$$XCODE_APP" ]; then \
			echo "Found $$XCODE_APP, selecting it..."; \
			if [ "$(SKIP_CONFIRM)" != "1" ]; then \
				printf "This will run: sudo xcode-select -s \"$$XCODE_APP\". Continue? [y/N] "; \
				read ans </dev/tty; case "$$ans" in [yY]) ;; *) echo "Aborted."; exit 1;; esac; \
			fi; \
			sudo xcode-select -s "$$XCODE_APP"; \
		else \
			echo "No Xcode installation found in /Applications."; \
			HAS_XCODES=0; \
			if PATH="$(ORIG_PATH)" command -v xcodes >/dev/null 2>&1; then \
				HAS_XCODES=1; \
			else \
				echo "Installing xcodes to manage Xcode versions..."; \
				PATH="$(ORIG_PATH)" brew install aria2 2>&1 || true; \
				if PATH="$(ORIG_PATH)" brew install xcodes 2>&1; then \
					HAS_XCODES=1; \
				else \
					echo "Could not install xcodes. See error above."; \
				fi; \
			fi; \
			if [ "$$HAS_XCODES" = "1" ]; then \
				echo "Downloading and installing the latest Xcode (this will take a while)..."; \
				PATH="$(ORIG_PATH)" xcodes install --latest --experimental-unxip; \
				XCODE_APP=$$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1); \
				if [ -z "$$XCODE_APP" ]; then \
					XCODE_APP=$$(PATH="$(ORIG_PATH)" xcodes installed | tail -1 | awk '{print $$NF}'); \
				fi; \
			fi; \
			if [ -z "$$XCODE_APP" ]; then \
				echo ""; \
				echo "Please install Xcode from the App Store or https://developer.apple.com/download/"; \
				echo "then re-run make setup."; \
				exit 1; \
			fi; \
			if [ "$(SKIP_CONFIRM)" != "1" ]; then \
				printf "This will run: sudo xcode-select -s \"$$XCODE_APP\". Continue? [y/N] "; \
				read ans </dev/tty; case "$$ans" in [yY]) ;; *) echo "Aborted."; exit 1;; esac; \
			fi; \
			sudo xcode-select -s "$$XCODE_APP"; \
		fi; \
	fi
	@if [ "$(SKIP_CONFIRM)" != "1" ]; then \
		printf "Accept the Xcode license agreement? [y/N] "; \
		read ans </dev/tty; \
		case "$$ans" in [yY]) sudo PATH="$(ORIG_PATH)" xcodebuild -license accept;; *) echo "Skipped license acceptance.";; esac; \
	else \
		sudo PATH="$(ORIG_PATH)" xcodebuild -license accept 2>/dev/null || true; \
	fi
	@test -f plists/iTerm2.plist || cp plists/dev-iTerm2.plist plists/iTerm2.plist
	@if ! test -x "$(HOMEBREW_PREFIX)/bin/python3"; then \
		PATH="$(ORIG_PATH)" brew install python3; \
		if ! PATH="$(ORIG_PATH)" brew link python@3 2>/dev/null; then \
			echo "brew link python@3 would overwrite existing symlinks:"; \
			PATH="$(ORIG_PATH)" brew link python@3 2>&1 | head -5; \
			if [ "$(SKIP_CONFIRM)" != "1" ]; then \
				printf "Overwrite these symlinks? [y/N] "; \
				read ans </dev/tty; case "$$ans" in [yY]) ;; *) echo "Aborted."; exit 1;; esac; \
			fi; \
			PATH="$(ORIG_PATH)" brew link --overwrite python@3; \
		fi; \
	fi
	@if ! PATH="$(ORIG_PATH)" brew list --cask sf-symbols >/dev/null 2>&1; then \
		INSTALL_SF=1; \
		if [ "$(SKIP_CONFIRM)" != "1" ]; then \
			printf "sf-symbols is a .pkg installer that requires sudo. Install it now? [y/N] "; \
			read ans </dev/tty; case "$$ans" in [yY]) ;; *) INSTALL_SF=0; echo "Skipped sf-symbols.";; esac; \
		fi; \
		if [ "$$INSTALL_SF" = "1" ]; then \
			PATH="$(ORIG_PATH)" brew install --cask sf-symbols || \
			{ echo ""; echo "WARNING: sf-symbols installation failed (requires sudo)."; \
			  echo "  Ask your admin to run: brew install --cask sf-symbols"; echo ""; }; \
		fi; \
	fi
	@$(HOMEBREW_PREFIX)/bin/python3 -c "import objc" 2>/dev/null || $(HOMEBREW_PREFIX)/bin/pip3 install --break-system-packages pyobjc
	PATH="$(ORIG_PATH)" xcodebuild -downloadComponent MetalToolchain || \
		echo "WARNING: Metal Toolchain download failed. You can retry later with: xcodebuild -downloadComponent MetalToolchain"
	@echo ""
	@echo "Setup complete. Run 'make paranoid-deps' to build native dependencies."

doctor:
	@echo "$(APP_NAME) build environment — $(TARGET_ARCH)"
	@echo ""
	@printf "  %-18s" "Homebrew:"; (PATH="$(ORIG_PATH)" brew --version 2>/dev/null | head -1) || echo "NOT FOUND"
	@printf "  %-18s" "Homebrew prefix:"; echo "$(HOMEBREW_PREFIX)"
	@printf "  %-18s" "Xcode:"; (xcodebuild -version 2>/dev/null | tr '\n' ' ' && echo) || echo "NOT FOUND"
	@printf "  %-18s" "xcode-select:"; (xcode-select -p 2>/dev/null) || echo "NOT FOUND"
	@printf "  %-18s" "xcodes:"; (PATH="$(ORIG_PATH)" xcodes version 2>/dev/null) || echo "not installed"
	@printf "  %-18s" "python3 (brew):"; ver=$$($(HOMEBREW_PREFIX)/bin/python3 --version 2>/dev/null); \
		if [ -z "$$ver" ]; then echo "NOT FOUND — run make setup"; \
		elif echo "$$ver" | grep -q "^Python 3"; then echo "$$ver"; \
		else echo "$$ver (WARNING: needs Python 3)"; fi
	@printf "  %-18s" "pyobjc:"; ($(HOMEBREW_PREFIX)/bin/python3 -c "import objc; print('installed')" 2>/dev/null) || echo "NOT FOUND"
	@printf "  %-18s" "sf-symbols:"; (PATH="$(ORIG_PATH)" brew list --cask sf-symbols >/dev/null 2>&1 && echo "installed") || echo "NOT FOUND"

TAGS:
	find . -name "*.[mhMH]" -exec etags -o ./TAGS -a '{}' +

install: | Deployment backup-old-iterm
	cp -R "$(BUILD_DIR)/Deployment/$(APP_BUNDLE)" "$(APPS)"

Development:
	echo "Using PATH for build: $(PATH)"
	cp plists/dev-iTerm2.plist plists/iTerm2.plist
	mkdir -p "$(BUILD_HOME)/.cache/clang" "$(BUILD_HOME)/Library/Caches" && \
	HOME="$(BUILD_HOME)" $(XCODEBUILD_ITERM) -configuration Development -destination 'platform=macOS' -skipPackagePluginValidation $(SIGNING_FLAGS) $(ARCH_FLAGS) SYMROOT="$(BUILD_DIR)" -derivedDataPath "$(DERIVED_DATA_DIR)" && \
	chmod -R go+rX $(BUILD_DIR)/Development

Beta:
	cp plists/beta-iTerm2.plist plists/iTerm2.plist
	mkdir -p "$(BUILD_HOME)/.cache/clang" "$(BUILD_HOME)/Library/Caches" && \
	HOME="$(BUILD_HOME)" $(XCODEBUILD_ITERM) -configuration Beta -destination 'platform=macOS' -skipPackagePluginValidation $(SIGNING_FLAGS) $(ARCH_FLAGS) SYMROOT="$(BUILD_DIR)" -derivedDataPath "$(DERIVED_DATA_DIR)" ENABLE_ADDRESS_SANITIZER=NO && \
	chmod -R go+rX $(BUILD_DIR)/Beta

Deployment:
	mkdir -p "$(BUILD_HOME)/.cache/clang" "$(BUILD_HOME)/Library/Caches" && \
	HOME="$(BUILD_HOME)" $(XCODEBUILD_ITERM) -configuration Deployment -destination 'platform=macOS' -skipPackagePluginValidation $(SIGNING_FLAGS) $(ARCH_FLAGS) SYMROOT="$(BUILD_DIR)" -derivedDataPath "$(DERIVED_DATA_DIR)" ENABLE_ADDRESS_SANITIZER=NO && \
	chmod -R go+rX $(BUILD_DIR)/Deployment

Nightly: force
	cp plists/nightly-iTerm2.plist plists/iTerm2.plist
	mkdir -p "$(BUILD_HOME)/.cache/clang" "$(BUILD_HOME)/Library/Caches" && \
	HOME="$(BUILD_HOME)" $(XCODEBUILD_ITERM) -configuration Nightly -destination 'platform=macOS' -skipPackagePluginValidation $(SIGNING_FLAGS) $(ARCH_FLAGS) SYMROOT="$(BUILD_DIR)" -derivedDataPath "$(DERIVED_DATA_DIR)" ENABLE_ADDRESS_SANITIZER=NO
	chmod -R go+rX $(BUILD_DIR)/Nightly

open: Development
	mkdir -p "$(RUN_DIR)"
	cd "$(RUN_DIR)" && open -W -n "$(BUILD_DIR)/Development/$(APP_BUNDLE)" --args -suite "$(SUITE)"

run: Development
	mkdir -p "$(RUN_DIR)"
	( cd "$(RUN_DIR)" && exec "$(BUILD_DIR)/Development/$(APP_BUNDLE)/Contents/MacOS/$(APP_EXECUTABLE)" -suite "$(SUITE)" ) & \
	pid=$$!; \
	trap 'kill $$pid 2>/dev/null' INT TERM; \
	( sleep 1 && osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $$pid) to true" >/dev/null 2>&1 ) & \
	wait $$pid

runbg: Development
	mkdir -p "$(RUN_DIR)"
	( cd "$(RUN_DIR)" && exec "$(BUILD_DIR)/Development/$(APP_BUNDLE)/Contents/MacOS/$(APP_EXECUTABLE)" -suite "$(SUITE)" ) & \
	pid=$$!; \
	trap 'kill $$pid 2>/dev/null' INT TERM; \
	( sleep 1 && osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $$pid) to true" >/dev/null 2>&1 ) & \

watch: Development
	mkdir -p "$(RUN_DIR)"
	cd "$(RUN_DIR)" && "$(CURDIR)/tools/run.sh" "$(BUILD_DIR)/Development/$(APP_BUNDLE)/Contents/MacOS/$(APP_EXECUTABLE)" "$(BUILD_DIR)" -suite "$(SUITE)"

devzip: Development
	cd $(BUILD_DIR)/Development && \
	zip -r $(APP_NAME)-$(NAME).zip $(APP_BUNDLE)

zip: Deployment
	cd $(BUILD_DIR)/Deployment && \
	zip -r $(APP_NAME)-$(NAME).zip $(APP_BUNDLE)

clean:
	rm -rf "$(BUILD_DIR)"
	rm -f *~
	rm -rf ThirdParty && git checkout ThirdParty
	git checkout last-xcode-version

backup-old-iterm:
	if [[ -d $(APPS)/$(APP_BUNDLE).bak ]] ; then rm -fr $(APPS)/$(APP_BUNDLE).bak ; fi
	if [[ -d $(APPS)/$(APP_BUNDLE) ]] ; then \
	/bin/mv $(APPS)/$(APP_BUNDLE) $(APPS)/$(APP_BUNDLE).bak ;\
	 cp $(ITERM_CONF_PLIST) $(APPS)/$(APP_BUNDLE).bak/Contents/ ; \
	fi

restart:
	PATH=$(ORIG_PATH) /usr/bin/open /Applications/$(APP_BUNDLE) &
	/bin/kill -TERM $(ITERM_PID)

release:
	cp plists/release-iTerm2.plist plists/iTerm2.plist
	make Deployment

preview:
	cp plists/preview-iTerm2.plist plists/iTerm2.plist
	make Deployment

pwmadapters: force
	cd pwmplugin/ && ./build.sh

paranoid-deps: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" deps
	xcodebuild -version > last-xcode-version

paranoid-pwmadapters: force
	/usr/bin/sandbox-exec -f deps.sb $(MAKE) BUILD_DIR="$(BUILD_DIR)" pwmadapters

# You probably want make paranoid-deps to avoid depending on Homebrew stuff.
deps: force pwmadapters

# Regenerate NSCharacterSet+iTerm.m and iTermCharacterSets.m from latest Unicode data.
# Run this when a new Unicode version is released.
unicode:
	rm -rf tools/.unicode_cache
	python3 tools/generate_nscharacterset.py

DepsIfNeeded: force
	tools/rebuild-deps-if-needed

cleandeps: force

test: force
	tools/run_tests.expect ModernTests

force:
