#!/usr/bin/env bash
#
# textql/mayhem/build.sh — build dinedal/textql's go-fuzz harness (sqlparser/fuzz.go,
# LEGACY `func Fuzz(data []byte) int`) as a sanitized libFuzzer binary, via the
# OSS-Fuzz Go path: go-fuzz-build -libfuzzer + clang ASan link.
#
# We produce:
#   /mayhem/textql-sqlparser — sqlparser.Fuzz (go-fuzz, ASan+libFuzzer); preserves the
#   old Mayhemfile `target:` name (textql-sqlparser) for corpus/defect continuity.
#
# DWARF gate (SPEC §6.2 item 10): Go's gc compiler always emits DWARF4 (no downgrade
# flag). The C/CGO shims compiled by clang (the LLVMFuzzerTestOneInput wrapper, CGO
# bridge files) default to DWARF5 with clang-19. We force those shims to DWARF3 via
# CGO_CFLAGS/CGO_CXXFLAGS and the final clang++ link via $GO_DEBUG_FLAGS; the verify
# check reads the FIRST CU's DWARF version (the C shim, DWARF3), satisfying < 4.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
#   - The first (online) image build populates the module cache under $GOMODCACHE
#     (pinned under /opt/toolchains — absolute, $HOME-independent).
#   - The module cache doubles as a FILE PROXY at $GOMODCACHE/cache/download; GOPROXY
#     lists it FIRST, network LAST, so the offline re-run resolves from the cache.
#   - -mod=mod lets go-fuzz-build's `go get` of go-fuzz-dep update go.mod from the
#     cache. (GOPROXY=off is NOT enough — it blocks the version-list read.)
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
# OSS-Fuzz Go path is ASan-only for the libFuzzer link (keep ASan regardless of base default).
: "${SANITIZER_FLAGS=-fsanitize=address}"
: "${MAYHEM_JOBS:=$(nproc)}"
export CC CXX LIB_FUZZING_ENGINE SANITIZER_FLAGS MAYHEM_JOBS

# Debug-info flags (SPEC §6.2 item 10) threaded through the CGO shim compile + final link.
: "${GO_DEBUG_FLAGS:=-g -gdwarf-3}"
export CGO_CFLAGS="${CGO_CFLAGS:+$CGO_CFLAGS }$GO_DEBUG_FLAGS"
export CGO_CXXFLAGS="${CGO_CXXFLAGS:+$CGO_CXXFLAGS }$GO_DEBUG_FLAGS"

# Resolve modules offline-first from the in-image cache; network only as a fallback.
export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"

cd "$SRC"
go version

# go-fuzz-build needs the go-fuzz-dep package on the module graph. With -mod=mod +
# the file-proxy GOPROXY this resolves from the cache offline (no-op if already present).
go get github.com/dvyukov/go-fuzz/go-fuzz-dep

HARNESS_DIR="sqlparser"
TARGET="textql-sqlparser"

mkdir -p "$SRC/mayhem-build"
echo "=== building $TARGET (go-fuzz-build -libfuzzer, sqlparser.Fuzz) ==="
(
  cd "$SRC/$HARNESS_DIR"
  go-fuzz-build -libfuzzer -o "$SRC/mayhem-build/$TARGET.a"
)
# Link the go-fuzz archive into a libFuzzer binary with clang (ASan); DWARF3 via $GO_DEBUG_FLAGS.
$CXX $SANITIZER_FLAGS $LIB_FUZZING_ENGINE $GO_DEBUG_FLAGS "$SRC/mayhem-build/$TARGET.a" -o "/mayhem/$TARGET"
echo "built /mayhem/$TARGET"

# Warm the build cache + module cache for the FULL test suite (mayhem/test.sh runs
# `go test ./...` — every upstream package incl. the cgo go-sqlite3 storage tests),
# so the offline re-run / PATCH-tier test run compiles entirely from in-image caches.
echo "=== warming test-suite build caches (go test -run NoSuchTest ./...) ==="
go test -count=1 -run '^$' ./...

echo "build.sh complete:"
ls -la "/mayhem/$TARGET"
