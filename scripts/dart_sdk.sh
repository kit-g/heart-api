#!/usr/bin/env bash
# Prints the bin/ directory of the Dart SDK this repo builds with, or nothing
# when the dart on PATH is already one. pages/ resolves only below Dart 3.14
# until Jaspr releases for analyzer 13 (pages/pubspec.yaml), and CI pins
# setup-dart to the same version, so a machine whose default dart is newer
# (Flutter ships one) gets that version here, downloaded once into
# ~/.cache/heart. HEART_DART_SDK, an SDK's root, wins over both.
#
# The Makefile and scripts/pages.sh put the answer first on PATH:
#
#   bin="$(scripts/dart_sdk.sh)" && PATH="${bin:+$bin:}$PATH"
#
# When Jaspr moves, drop the pin here, in pages/pubspec.yaml and in the
# workflows together.
set -euo pipefail

PINNED=3.13.7

if [ -n "${HEART_DART_SDK:-}" ]; then
  echo "$HEART_DART_SDK/bin"
  exit 0
fi

# No dart at all (a Python-only CI job runs make too): nothing to pick.
command -v dart >/dev/null || exit 0

# `dart --version` prints e.g. "Dart SDK version: 3.14.0 (stable) ..."
current="$(dart --version 2>&1 | sed -n 's/^Dart SDK version: \([0-9]*\)\.\([0-9]*\)\..*/\1 \2/p')"
if [ -n "$current" ]; then
  read -r major minor <<<"$current"
  if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 14 ]; }; then
    exit 0
  fi
fi

SDK="${XDG_CACHE_HOME:-$HOME/.cache}/heart/dart-sdk-$PINNED"
if [ ! -x "$SDK/bin/dart" ]; then
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) platform=macos-arm64 ;;
    Darwin-x86_64) platform=macos-x64 ;;
    Linux-x86_64) platform=linux-x64 ;;
    Linux-aarch64 | Linux-arm64) platform=linux-arm64 ;;
    *) echo "dart_sdk.sh: no Dart $PINNED download for $(uname -sm); set HEART_DART_SDK" >&2; exit 1 ;;
  esac
  echo "dart_sdk.sh: fetching Dart $PINNED into $SDK (once)" >&2
  tmp="$(mktemp -d)"
  trap 'rm -r "$tmp"' EXIT
  curl -fsSL -o "$tmp/sdk.zip" \
    "https://storage.googleapis.com/dart-archive/channels/stable/release/$PINNED/sdk/dartsdk-$platform-release.zip"
  unzip -q "$tmp/sdk.zip" -d "$tmp"
  mkdir -p "$(dirname "$SDK")"
  mv "$tmp/dart-sdk" "$SDK"
fi
echo "$SDK/bin"
