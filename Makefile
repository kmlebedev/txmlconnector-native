## txmlconnector-native: pure-Go TRANSAQ client, DLL-compatible XML connector,
## C ABI drop-in library and the reverse-engineering toolkit of the vendor DLL.
## See README.md and AGENTS.md; the DLL update runbook is docs/dll-update.md.

## Reference DLL kept in the repository root (the single source of truth).
TXC_VERSION ?= 6.47.2.26.4
TXC_DLL     ?= txmlconnector64-$(TXC_VERSION).dll

## In a restricted sandbox (DSH workspace-write) the global Go cache is not
## writable, so the targets fall back to a repository-local cache.
VERIFY_GOCACHE = GOCACHE="$${GOCACHE:-$(CURDIR)/.cache/go-build}"

.PHONY: help compile test vet fmt-check verify cross re-check re-check-full re-selftest \
	dll-sha dll-inventory dll-exports \
	cabi cabi-so cabi-dylib cabi-zig cabi-test cabi-live-test cabi-conformance

help: ## List the targets.
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-18s %s\n", $$1, $$2}'

compile: ## Regenerate proto/marketdata (protoc + protoc-gen-go).
	protoc proto/marketdata/trade.proto --go_out=. --go_opt=paths=source_relative

test: ## go test ./...
	$(VERIFY_GOCACHE) go test ./...

vet: ## go vet ./...
	$(VERIFY_GOCACHE) go vet ./...

fmt-check: ## gofmt -l over tracked Go files (must be empty).
	@out="$$(git ls-files '*.go' | xargs gofmt -l)"; if [ -n "$$out" ]; then echo "gofmt needed:"; echo "$$out"; exit 1; fi

cross: ## CGO_ENABLED=0 cross-builds: linux/amd64, linux/arm64, darwin/arm64, windows/amd64.
	$(VERIFY_GOCACHE) CGO_ENABLED=0 GOOS=linux   GOARCH=amd64 go build ./...
	$(VERIFY_GOCACHE) CGO_ENABLED=0 GOOS=linux   GOARCH=arm64 go build ./...
	$(VERIFY_GOCACHE) CGO_ENABLED=0 GOOS=darwin  GOARCH=arm64 go build ./...
	$(VERIFY_GOCACHE) CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build ./...

verify: fmt-check ## Checks required by AGENTS.md before every commit.
	$(VERIFY_GOCACHE) go vet ./...
	$(VERIFY_GOCACHE) go build ./...
	$(MAKE) --no-print-directory cross
	$(VERIFY_GOCACHE) go test -race ./...

## ---- Reverse engineering (tools/re/README.md) ------------------------------

re-check: ## Environment readiness for RE-1..RE-4 (never prints secrets).
	tools/re/check_env.sh

re-check-full: ## re-check plus go build/test/-race and cross-builds.
	tools/re/check_env.sh --full

re-selftest: ## Python model of the protocol (tools/re/py): offline self-test.
	python3 tools/re/py/selftest.py

dll-sha: ## SHA-256 of the reference DLL (compare with AGENTS.md / docs/dll-update.md).
	@shasum -a 256 "$(TXC_DLL)"

dll-inventory: ## Read-only PE inventory of the DLL -> docs/research/binary-inventory-<ver>.json.
	python3 docs/research/inspect_binary.py "$(TXC_DLL)" docs/research/binary-inventory-$(TXC_VERSION).json

dll-exports: ## Export table (names and ordinals) of the reference DLL.
	$(VERIFY_GOCACHE) go run ./tools/cabi/pe-repro -exports "$(TXC_DLL)"

## ---- C ABI compat library (docs/COMPATIBILITY.md) ---------------------------
## The wrapper is cgo; native/... stays pure Go. "make cabi" picks the current OS.

CABI_GOARCH ?= $(shell go env GOARCH)
CABI_LIB_BASE = bin/libtxmlconnector

cabi-so: ## c-shared .so for the current Linux arch.
	mkdir -p bin
	CGO_ENABLED=1 GOARCH=$(CABI_GOARCH) go build -buildmode=c-shared -trimpath -ldflags "-X main.defaultVersion=$(TXC_VERSION)" -o $(CABI_LIB_BASE).so ./cmd/connector
	cp -f cmd/connector/include/txmlconnector.h bin/txmlconnector.h
	cp -f $(CABI_LIB_BASE).so bin/libtxmlconnector64.so

cabi-dylib: ## c-shared .dylib for the current macOS arch.
	mkdir -p bin
	CGO_ENABLED=1 GOARCH=$(CABI_GOARCH) go build -buildmode=c-shared -trimpath -ldflags "-X main.defaultVersion=$(TXC_VERSION)" -o $(CABI_LIB_BASE).dylib ./cmd/connector
	cp -f cmd/connector/include/txmlconnector.h bin/txmlconnector.h
	cp -f $(CABI_LIB_BASE).dylib bin/libtxmlconnector64.dylib

ifeq ($(shell go env GOOS),darwin)
cabi: cabi-dylib
CABI_TEST_LIB = $(CABI_LIB_BASE).dylib
CABI_TEST_ENV = DYLD_LIBRARY_PATH=bin
CABI_TEST_LIBS = -Lbin -ltxmlconnector
else
cabi: cabi-so
CABI_TEST_LIB = $(CABI_LIB_BASE).so
CABI_TEST_ENV = LD_LIBRARY_PATH=bin
CABI_TEST_LIBS = -Lbin -ltxmlconnector -ldl
endif

## C9 release builds: Zig is the C toolchain for every target (zig cc -target
## ...; Linux pinned to glibc 2.17). macOS targets need the macOS SDK, so they
## are built on a macOS host. Output: bin/zig/<target>/.
ifeq ($(shell go env GOOS),darwin)
CABI_ZIG_TARGETS ?= linux-amd64 linux-arm64 windows-amd64 macos-arm64 macos-amd64
else
CABI_ZIG_TARGETS ?= linux-amd64 linux-arm64 windows-amd64
endif
cabi-zig: ## Reproducible Zig builds of the C ABI library (bin/zig/<target>).
	TXC_VERSION=$(TXC_VERSION) tools/cabi/zig_build.sh bin/zig $(CABI_ZIG_TARGETS)

cabi-live-test: cabi ## Live read-only C ABI test (C4): source ~/re/demo.env first. No trading commands.
	$(CC) -I cmd/connector/include -o bin/abi_live cmd/connector/testdata/abi_live.c $(CABI_TEST_LIBS)
	mkdir -p $${TXC_LOG_DIR:-bin/abi-live-logs}
	$(CABI_TEST_ENV) ./bin/abi_live $(CABI_TEST_LIB)

cabi-test: cabi ## Portable dlopen/LoadLibrary ABI test (all 9 exports, error paths, callback).
	$(CC) -I cmd/connector/include -o bin/abi_test cmd/connector/testdata/abi_test.c $(CABI_TEST_LIBS)
	$(CABI_TEST_ENV) ./bin/abi_test $(CABI_TEST_LIB)

cabi-conformance: cabi ## C5: replay cabi_scenarios.json and compare with the reference DLL byte-for-byte.
	$(CC) -I cmd/connector/include -o bin/abi_conformance cmd/connector/testdata/abi_conformance.c
	$(CABI_TEST_ENV) ./bin/abi_conformance $(CABI_TEST_LIB) cmd/connector/testdata/cabi_scenarios.json
