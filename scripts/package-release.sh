#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Shards reads the version from shard.yml, including quoted YAML values.
version=$(shards version)
if [[ ! "$version" =~ ^[0-9][0-9A-Za-z.+-]*$ ]]; then
  echo "Invalid release version from shard.yml: $version" >&2
  exit 1
fi

release_name="hnreader-${version}-fedora43-x86_64"
release_dir="dist/$release_name"
archive="${release_name}.tar.gz"

# Recreate the staging directory so removed/renamed files cannot leak into a release.
mkdir -p dist
rm -rf "$release_dir"
rm -f "dist/$archive" "dist/$archive.sha256"
install -Dm755 bin/hnreader "$release_dir/bin/hnreader"
install -Dm644 data/hnreader.makridenko.com.desktop \
  "$release_dir/share/applications/hnreader.makridenko.com.desktop"
install -Dm644 data/hnreader.makridenko.com.svg \
  "$release_dir/share/icons/hicolor/scalable/apps/hnreader.makridenko.com.svg"
install -m644 LICENSE README.md "$release_dir/"

tar -czf "dist/$archive" -C dist "$release_name"
# Record only the filename, so verification works wherever the pair is downloaded.
(cd dist && sha256sum "$archive" > "$archive.sha256")
