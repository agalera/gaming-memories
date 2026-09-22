SHELL := /bin/bash

.DEFAULT_GOAL := help

FVM ?= fvm
FLUTTER := $(FVM) flutter
DART := $(FVM) dart
DEVICE ?= linux
PLATFORM ?= linux
BUILD_MODE ?= debug
ARGS ?=
VERSION ?= $(shell sed -n 's/^version: \([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml)
BUILD_NUMBER ?= 1
DIST_DIR ?= dist
TAG ?= $(shell git describe --tags --exact-match 2>/dev/null)
PACKAGE_ENV := GM_VERSION=$(VERSION) DIST_DIR=$(DIST_DIR)

.PHONY: help setup deps outdated upgrade devices doctor run run-linux run-macos run-windows analyze format format-check test check icons icons-reset gallery-preview open-xcode build build-linux build-macos build-windows package-linux package-macos package-windows release-macos clean

help: ## Show the available commands.
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target> [VARIABLE=value]\n\nTargets:\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Install the configured Flutter SDK and project packages.
	$(FVM) install
	$(FLUTTER) pub get

deps: ## Get project packages.
	$(FLUTTER) pub get

outdated: ## Show package updates.
	$(FLUTTER) pub outdated

upgrade: ## Update packages within the current version limits.
	$(FLUTTER) pub upgrade

devices: ## Show available Flutter devices.
	$(FLUTTER) devices

doctor: ## Show Flutter environment details.
	$(FLUTTER) doctor -v

run: ## Run the app. Use DEVICE=macos or DEVICE=windows when needed.
	$(FLUTTER) run -d $(DEVICE) $(ARGS)

run-linux: ## Run the Linux app.
	$(MAKE) run DEVICE=linux ARGS="$(ARGS)"

run-macos: ## Run the macOS app.
	$(MAKE) run DEVICE=macos ARGS="$(ARGS)"

run-windows: ## Run the Windows app.
	$(MAKE) run DEVICE=windows ARGS="$(ARGS)"

analyze: ## Run static analysis.
	$(FLUTTER) analyze

format: ## Format Dart source and test files.
	$(DART) format lib test

format-check: ## Check Dart format without file changes.
	$(DART) format --output=none --set-exit-if-changed lib test

test: ## Run all tests. Use ARGS for extra Flutter test options.
	$(FLUTTER) test $(ARGS)

check: format-check analyze test ## Run all source checks.

icons: ## Generate desktop icons from assets/logo.png.
	./tool/generate_desktop_icons.sh

icons-reset: ## Reset the OS icon cache so a rebuilt app shows the current icon.
	./tool/reset_icon_cache.sh $(ARGS)

gallery-preview: ## Render LIBRARY into a servable gallery and serve it. Set LIBRARY and optionally PORT.
	$(DART) run tool/render_demo_gallery.dart "$(LIBRARY)" build/gallery-preview
	@echo "Serving build/gallery-preview on http://127.0.0.1:$(or $(PORT),8145)"
	@cd build/gallery-preview && python3 -m http.server $(or $(PORT),8145)

open-xcode: ## Open the macOS runner in Xcode.
	open macos/Runner.xcworkspace

build: ## Build a desktop app. Set PLATFORM and BUILD_MODE as needed.
	$(FLUTTER) build $(PLATFORM) --$(BUILD_MODE) $(ARGS)

build-linux: ## Build the Linux app.
	$(MAKE) build PLATFORM=linux BUILD_MODE=$(BUILD_MODE) ARGS="$(ARGS)"

build-macos: ## Build the macOS app.
	$(MAKE) build PLATFORM=macos BUILD_MODE=$(BUILD_MODE) ARGS="$(ARGS)"

build-windows: ## Build the Windows app.
	$(MAKE) build PLATFORM=windows BUILD_MODE=$(BUILD_MODE) ARGS="$(ARGS)"

package-linux: ## Build the Linux deb, rpm and Arch packages into DIST_DIR.
	$(FLUTTER) build linux --release --build-name=$(VERSION) --build-number=$(BUILD_NUMBER)
	$(PACKAGE_ENV) ./tool/package_linux.sh

package-macos: ## Build the macOS .dmg into DIST_DIR, signing it when a certificate is available.
	$(FLUTTER) build macos --release --build-name=$(VERSION) --build-number=$(BUILD_NUMBER)
	$(PACKAGE_ENV) ./tool/package_macos.sh

package-windows: ## Build the Windows self-executing .exe and .zip into DIST_DIR.
	$(FLUTTER) build windows --release --build-name=$(VERSION) --build-number=$(BUILD_NUMBER)
	$(PACKAGE_ENV) pwsh -NoProfile -File ./tool/fetch_sfx_module.ps1
	$(PACKAGE_ENV) pwsh -NoProfile -File ./tool/package_windows.ps1

release-macos: ## Attach a signed macOS .dmg to the GitHub release for TAG.
	@test -n "$(TAG)" || { echo "Set TAG=vX.Y.Z, or check out the tag." >&2; exit 1; }
	$(MAKE) package-macos VERSION=$(TAG:v%=%) BUILD_NUMBER=$(BUILD_NUMBER) DIST_DIR=$(DIST_DIR)
	TAG=$(TAG) GM_VERSION=$(TAG:v%=%) DIST_DIR=$(DIST_DIR) ./tool/release_macos.sh

clean: ## Remove generated build files.
	$(FLUTTER) clean
	rm -rf $(DIST_DIR)
