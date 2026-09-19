SHELL := /bin/bash

.DEFAULT_GOAL := help

FVM ?= fvm
FLUTTER := $(FVM) flutter
DART := $(FVM) dart
DEVICE ?= linux
PLATFORM ?= linux
BUILD_MODE ?= debug
ARGS ?=

.PHONY: help setup deps outdated upgrade devices doctor run run-linux run-macos run-windows analyze format format-check test check build build-linux build-macos build-windows clean

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

build: ## Build a desktop app. Set PLATFORM and BUILD_MODE as needed.
	$(FLUTTER) build $(PLATFORM) --$(BUILD_MODE) $(ARGS)

build-linux: ## Build the Linux app.
	$(MAKE) build PLATFORM=linux BUILD_MODE=$(BUILD_MODE) ARGS="$(ARGS)"

build-macos: ## Build the macOS app.
	$(MAKE) build PLATFORM=macos BUILD_MODE=$(BUILD_MODE) ARGS="$(ARGS)"

build-windows: ## Build the Windows app.
	$(MAKE) build PLATFORM=windows BUILD_MODE=$(BUILD_MODE) ARGS="$(ARGS)"

clean: ## Remove generated build files.
	$(FLUTTER) clean
