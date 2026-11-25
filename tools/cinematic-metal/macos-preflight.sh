#!/usr/bin/env bash
# Read-only environment check for building the mcopt Metal module on Apple Silicon.
# Usage from repository root:
#   ./tools/cinematic-metal/macos-preflight.sh
#   ./tools/cinematic-metal/macos-preflight.sh --build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MODE="${1:-check}"

if [ "$#" -gt 1 ] || { [ "$MODE" != "check" ] && [ "$MODE" != "--build" ]; }; then
  echo "Usage: $0 [--build]" >&2
  exit 2
fi

ERRORS=0
WARNINGS=0

ok()   { printf '  [OK]   %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf '  [FAIL] %s\n' "$1"; ERRORS=$((ERRORS + 1)); }

version_major() {
  printf '%s\n' "$1" | awk -F. '{ print $1 + 0 }'
}

printf '\nCinematic Metal — macOS build preflight\n'
printf 'Repository: %s\n\n' "$REPO_ROOT"

if [ "$(uname -s)" != "Darwin" ]; then
  fail "This build requires macOS; detected $(uname -s). No build was attempted."
else
  ok "macOS host detected"
fi

ARCH="$(uname -m)"
if [ "$ARCH" = "arm64" ]; then
  ok "Apple Silicon host detected (arm64)"
else
  fail "Expected arm64 Apple Silicon; detected $ARCH. Run a native arm64 terminal, not an x86_64/Rosetta shell."
fi

if command -v sw_vers >/dev/null 2>&1; then
  MACOS_VERSION="$(sw_vers -productVersion)"
  if [ "$(version_major "$MACOS_VERSION")" -ge 15 ]; then
    ok "macOS $MACOS_VERSION satisfies the renderer's macOS 15 minimum"
  else
    fail "macOS $MACOS_VERSION is below the renderer's macOS 15 deployment target"
  fi
else
  fail "sw_vers is unavailable; cannot verify macOS version"
fi

if command -v xcode-select >/dev/null 2>&1 && xcode-select -p >/dev/null 2>&1; then
  ok "Xcode Command Line Tools selected: $(xcode-select -p)"
else
  fail "Xcode Command Line Tools are not selected. Install them with: xcode-select --install"
fi

if command -v xcrun >/dev/null 2>&1; then
  if CLANG_PATH="$(xcrun --find clang 2>/dev/null)"; then
    ok "Apple clang available: $CLANG_PATH"
  else
    fail "xcrun cannot find Apple clang; repair/install Xcode Command Line Tools"
  fi
  if SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)"; then
    ok "macOS SDK available: $SDK_VERSION"
  else
    fail "macOS SDK is unavailable through xcrun"
  fi
else
  fail "xcrun is unavailable; Xcode Command Line Tools are required"
fi

if command -v java >/dev/null 2>&1; then
  JAVA_VERSION_LINE="$(java -version 2>&1 | sed -n '1p')"
  JAVA_MAJOR="$(printf '%s\n' "$JAVA_VERSION_LINE" | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p')"
  if [ -z "$JAVA_MAJOR" ]; then
    JAVA_MAJOR="$(printf '%s\n' "$JAVA_VERSION_LINE" | sed -n 's/.* \([0-9][0-9]*\)\..*/\1/p')"
  fi
  if [ -n "$JAVA_MAJOR" ] && [ "$JAVA_MAJOR" -ge 25 ]; then
    ok "Java runtime: $JAVA_VERSION_LINE"
    JAVA_ARCH="$(java -XshowSettings:properties -version 2>&1 | sed -n 's/^[[:space:]]*os.arch = //p' | sed -n '1p')"
    case "$JAVA_ARCH" in
      aarch64|arm64) ok "Java runtime architecture: $JAVA_ARCH" ;;
      *) fail "Expected ARM64 Java; detected os.arch=${JAVA_ARCH:-unknown}. Select an ARM64 JDK." ;;
    esac
  else
    fail "Java 25 or newer is required; detected: ${JAVA_VERSION_LINE:-unknown}"
  fi
else
  fail "Java is not on PATH; install/select an ARM64 JDK 25 or newer"
fi

if command -v javac >/dev/null 2>&1; then
  JAVAC_VERSION="$(javac -version 2>&1)"
  JAVAC_MAJOR="$(printf '%s\n' "$JAVAC_VERSION" | sed -n 's/.* \([0-9][0-9]*\)\..*/\1/p')"
  if [ -n "$JAVAC_MAJOR" ] && [ "$JAVAC_MAJOR" -ge 25 ]; then
    ok "Java compiler: $JAVAC_VERSION"
  else
    fail "javac 25 or newer is required; detected: $JAVAC_VERSION"
  fi
else
  fail "javac is unavailable; a JDK (not only a JRE) is required"
fi

if [ -x "$REPO_ROOT/gradlew" ]; then
  ok "Gradle wrapper exists and is executable"
else
  fail "gradlew is missing or not executable at the repository root"
fi

for required in \
  "$REPO_ROOT/settings.gradle" \
  "$REPO_ROOT/gradle.properties" \
  "$REPO_ROOT/metal/build.gradle" \
  "$REPO_ROOT/metal/src/main/native/mcmetal.m" \
  "$REPO_ROOT/metal/src/main/native/mcshade.m"; do
  if [ -f "$required" ]; then
    ok "Found ${required#"$REPO_ROOT"/}"
  else
    fail "Missing required build input: ${required#"$REPO_ROOT"/}"
  fi
done

if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"
  if [ "$BRANCH" = "cinematic-metal" ]; then
    ok "Git branch is cinematic-metal"
  else
    warn "Current Git branch is '$BRANCH', not 'cinematic-metal'. Switch before editing or committing."
  fi
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    warn "Working tree has uncommitted changes; review them before building or switching branches."
  else
    ok "Git working tree is clean"
  fi
else
  warn "Git checkout not detected; branch and working-tree checks were skipped"
fi

printf '\n'
if [ "$ERRORS" -gt 0 ]; then
  printf 'Preflight failed: %s error(s), %s warning(s).\n' "$ERRORS" "$WARNINGS"
  printf 'No build was attempted. Fix the failed checks and run this script again.\n\n'
  exit 1
fi

printf 'Preflight passed: 0 errors, %s warning(s).\n' "$WARNINGS"
printf 'This checks build prerequisites only; it does not compile Metal or launch Minecraft.\n'
printf 'The mcopt module compiles its Objective-C native bridge with Apple clang and packages it in the JAR.\n\n'

if [ "$MODE" = "--build" ]; then
  printf 'Running the isolated baseline build: ./gradlew --no-daemon --no-parallel :metal:build\n\n'
  cd "$REPO_ROOT"
  ./gradlew --no-daemon --no-parallel :metal:build
  printf '\nBuild task completed. Inspect the Gradle output and metal/build/libs/ before treating it as a usable game mod.\n'
else
  printf 'Next command after a successful check:\n'
  printf '  cd "%s" && ./gradlew --no-daemon --no-parallel :metal:build\n\n' "$REPO_ROOT"
  printf 'To run the check and build in one step, use:\n'
  printf '  ./tools/cinematic-metal/macos-preflight.sh --build\n\n'
fi
