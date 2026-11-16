#!/bin/bash
# Builds the app for iOS, macOS and tvOS side by side and fails if any of them
# does. Run before merging a branch: a change that only ever gets built for the
# platform it was made on can break another one unnoticed (a macOS-only
# modifier left the tvOS build failing for several merges).
#
# Packages resolve once, up front, into the shared CLI package clone; the three
# builds then run side by side without resolving again (three resolves into one
# clone at once trip over each other). Each builds into its own -derivedDataPath
# (/tmp/streamen-check-<label>), unsigned, for a simulator or the Mac — no device
# or provisioning needed. Warnings are listed but don't fail the check.
#
# Usage: Scripts/check-all-platforms.sh [ios|macos|tvos …]   (default: all three)
set -uo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root" || exit 1
packages=~/Library/Developer/Streamen-SharedSPM
logs="$(mktemp -d -t streamen-check)"

destination() {
  case "$1" in
    ios) echo "generic/platform=iOS Simulator" ;;
    macos) echo "platform=macOS" ;;
    tvos) echo "generic/platform=tvOS Simulator" ;;
    *) echo "unknown platform: $1 (expected ios, macos or tvos)" >&2; return 1 ;;
  esac
}

platforms=("$@")
[ ${#platforms[@]} -eq 0 ] && platforms=(ios macos tvos)

echo "Resolving packages…"
if ! xcodebuild -resolvePackageDependencies -project Streamen.xcodeproj -scheme Streamen \
  -clonedSourcePackagesDirPath "$packages" >"$logs/resolve.log" 2>&1; then
  echo "✗ package resolution FAILED — errors:"
  grep -E "error:" "$logs/resolve.log" | sort -u | head -20 | sed 's/^/    /'
  echo "    full log: $logs/resolve.log"
  exit 1
fi

for platform in "${platforms[@]}"; do
  dest="$(destination "$platform")" || exit 2
  # A generic simulator destination also builds x86_64, which LibDovi doesn't
  # ship for; Apple-silicon simulators only need arm64.
  # Expanded as ${arch[@]+…} below: macOS's bash 3.2 treats an empty array
  # as unset under `set -u`, which failed the macOS build before it started.
  arch=()
  [ "$platform" != macos ] && arch=(ARCHS=arm64)
  echo "Building $platform…"
  xcodebuild build \
    -project Streamen.xcodeproj -scheme Streamen -configuration Debug \
    -destination "$dest" \
    -derivedDataPath "/tmp/streamen-check-$platform" \
    -clonedSourcePackagesDirPath "$packages" \
    -disableAutomaticPackageResolution \
    CODE_SIGNING_ALLOWED=NO ${arch[@]+"${arch[@]}"} \
    >"$logs/$platform.log" 2>&1 &
  pids+=("$!")
done

failed=0
for index in "${!platforms[@]}"; do
  platform="${platforms[$index]}"
  log="$logs/$platform.log"
  if wait "${pids[$index]}"; then
    warnings=$(grep -c "warning:" "$log" || true)
    echo "✓ $platform built ($warnings warning lines)"
  else
    failed=1
    echo "✗ $platform FAILED — errors:"
    grep -E "error:" "$log" | sort -u | head -20 | sed 's/^/    /'
    echo "    full log: $log"
  fi
done

[ "$failed" -eq 0 ] && rm -rf "$logs"
exit "$failed"
