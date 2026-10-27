SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

NIM_MAIN := src/nemohooks.nim
NIM_SRC := $(wildcard src/*.nim src/nemohooks/*.nim src/nemohooks/backends/*.nim examples/*.nim)
# Backends share names on purpose, so nothing imports them all and each is its own target.
NIM_CHECK := $(NIM_MAIN) $(wildcard src/nemohooks/backends/*.nim examples/*.nim)
TOOLS_DIR := .tools
NIMONY_VERSION := 0.6.3
# Overridable so one unpacked toolchain can serve several checkouts.
NIMONY_DIR ?= $(TOOLS_DIR)/nimony-$(NIMONY_VERSION)/nimony
NIMONY := $(NIMONY_DIR)/bin/nimony.exe
# --compat makes Nimony read the same nim.cfg Nim 2 uses.
NIMONY_FLAGS := --compat --os:android --cpu:arm64

.PHONY: help help-more lint check nimony-check fmt fmt-check require-nimony

lint: check fmt-check ## Type-check and check formatting - the same gate CI runs

check: # Type-check every module against the real android target
	@for f in $(NIM_CHECK); do 	  echo "nim check $$f"; 	  nim check --hints:off --path:src "$$f" || exit 1; 	done

# Local only: Nimony ships as a nightly zip a workflow cannot pin. Run it before pushing.
nimony-check: require-nimony ## Type-check the same sources with Nimony (Nim 3)
	@for f in $(NIM_CHECK); do 	  echo "nimony check $$f"; 	  $(NIMONY) check $(NIMONY_FLAGS) --path:src "$$f" || exit 1; 	done

require-nimony:
	@test -x "$(NIMONY)" || { \
	  echo "Nimony $(NIMONY_VERSION) not found in $(NIMONY_DIR)."; \
	  echo "Fetch it with:"; \
	  echo "  gh release download --repo nim-lang/nimony-website --pattern '*windows_amd64.zip' --dir $(TOOLS_DIR)"; \
	  echo "  unzip -o $(TOOLS_DIR)/nimony-*.zip -d $(TOOLS_DIR)/nimony-$(NIMONY_VERSION)"; \
	  exit 1; }

fmt-check: # Check formatting without rewriting anything
	@fail=0; tmp=$$(mktemp -d); \
	for f in $(NIM_SRC); do \
	  cp "$$f" "$$tmp/$$(basename $$f)"; \
	  nimpretty --maxLineLen:100 --out:"$$tmp/$$(basename $$f)" "$$f" >/dev/null 2>&1 || true; \
	  if ! diff -q "$$f" "$$tmp/$$(basename $$f)" >/dev/null; then \
	    echo "nimpretty: $$f is not formatted (run 'make fmt')"; fail=1; \
	  fi; \
	done; rm -rf "$$tmp"; \
	exit $$fail

fmt: ## Reformat the Nim sources in place
	@for f in $(NIM_SRC); do nimpretty --maxLineLen:100 "$$f"; done

### Commands with ## after and on the same line as the subcommand name are shown in the help message using the comment as the command description.
help: ## Output help about the make commands.
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

### Same rule as above but for a singular # and it will output every subcommand.
help-more: # Output extra help about the make commands.
	@grep -E '^[a-zA-Z_-]+:.*?# .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?# "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
