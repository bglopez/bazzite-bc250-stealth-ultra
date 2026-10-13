#!/usr/bin/env bash
# Install the pinned runtime unlock directly from its original upstream.
set -euo pipefail
share="${DESTDIR:-}/usr/share/bc250-40cu"
revision=$(cat "$share/vendor/bc250-cu-live-manager.UPSTREAM_REF")
[[ "$revision" =~ ^[a-f0-9]{40}$ ]]
source_url="https://raw.githubusercontent.com/WinnieLV/bc250-cu-live-manager/$revision"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
for file in bc250-cu-live-manager.sh README.md; do
  curl -fsSL --retry 3 "$source_url/$file" -o "$workdir/$file"
done
(cd "$workdir" && sha256sum --check "$share/SHA256SUMS")
bash -n "$workdir/bc250-cu-live-manager.sh"
destination="$share/vendor/bc250-cu-live-manager"
install -d "$destination"
install -m 0755 "$workdir/bc250-cu-live-manager.sh" "$destination/"
install -m 0644 "$workdir/README.md" "$destination/"
