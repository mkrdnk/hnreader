#!/usr/bin/env bash
# GI bindings use installed typelibs, not C headers. Some distributions ship
# the unversioned linker names only in -devel packages. Provide those names
# locally when the matching runtime ABI is already installed.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/lib
read -r -a compiler <<< "${CC:-cc}"

for soname in \
  libgirepository-1.0.so.1 \
  libgtk-4.so.1 \
  libadwaita-1.so.0 \
  libwebkitgtk-6.0.so.4 \
  libjavascriptcoregtk-6.0.so.1; do
  linker_name="${soname%.so.*}.so"
  library=$("${compiler[@]}" -print-file-name="$linker_name")
  if [[ ! -f "$library" ]]; then
    library=$("${compiler[@]}" -print-file-name="$soname")
  fi
  if [[ ! -f "$library" ]]; then
    printf 'Missing library: %s\n' "$soname" >&2
    printf 'On Fedora, install: sudo dnf install gtk4-devel libadwaita-devel webkitgtk6.0-devel gobject-introspection-devel\n' >&2
    exit 1
  fi
  ln -sfn "$(realpath "$library")" ".build/lib/$linker_name"
done
