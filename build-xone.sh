#!/usr/bin/env bash
set -euo pipefail
KVER="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n1)"
test -n "$KVER"
echo "Building xone for $KVER"
dnf5 -y install git make gcc "kernel-devel-uname-r = $KVER" || {
  echo "Matching kernel-devel unavailable; refusing mismatched build." >&2
  exit 1
}
: "${XONE_COMMIT:?Set XONE_COMMIT to a reviewed full upstream commit SHA}"
git clone https://github.com/honjow/xonedo /tmp/xonedo
cd /tmp/xonedo
git checkout --detach "$XONE_COMMIT"
make KERNELRELEASE="$KVER" -j"$(nproc)"
make KERNELRELEASE="$KVER" install
depmod -a "$KVER"
