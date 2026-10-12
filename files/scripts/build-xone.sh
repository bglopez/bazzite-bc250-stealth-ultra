#!/usr/bin/env bash
set -euo pipefail
# Intentionally fail closed on mismatched or unavailable kernel development files.
KVER="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n1)"
test -n "$KVER"
echo "Building xone for $KVER"
dnf5 -y install git make gcc "kernel-devel-uname-r = $KVER" || {
  echo "Matching kernel-devel unavailable. Do not install modules for a different kernel." >&2
  exit 1
}
# Resolve the current upstream commit at build time.
XONE_COMMIT="$(git ls-remote https://github.com/honjow/xonedo.git HEAD | cut -f1)"
test -n "$XONE_COMMIT" || { echo "Could not resolve xonedo HEAD" >&2; exit 1; }
echo "Using xonedo commit: $XONE_COMMIT"
git clone https://github.com/honjow/xonedo /tmp/xonedo
cd /tmp/xonedo
git checkout --detach "$XONE_COMMIT"
# xone's Makefile/install interface must be validated for the selected revision.
KDIR="/usr/src/kernels/$KVER"
test -d "$KDIR" || { echo "Kernel headers missing at $KDIR" >&2; exit 1; }
# xonedo Makefile uses KDIR/KVERSION, not KERNELRELEASE.
make KVERSION="$KVER" KDIR="$KDIR" -j"$(nproc)"
# Avoid upstream install target: it invokes uname-based uninstall/install scripts.
install -d "/usr/lib/modules/$KVER/extra/xonedo"
find . -maxdepth 1 -name "*.ko" -exec install -m 0644 {} "/usr/lib/modules/$KVER/extra/xonedo/" \;
test -n "$(find /usr/lib/modules/$KVER/extra/xonedo -name '*.ko' -print -quit)"
depmod -a "$KVER"
