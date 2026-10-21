#!/usr/bin/env bash
# Build a patched amdgpu for the base image's exact kernel.
#
# The BC-250 kernel fixes are amdgpu changes, so they need a rebuilt module
# rather than a userspace patch. The module is built against the base
# image's own kernel (same version, same OpenGamingCollective changes), so
# its vermagic matches and it can replace the stock module in the image.
#
# This stage never fails the image build. A kernel bump upstream can make
# the patches stop applying, and the right response to that is to ship the
# image with the stock kernel and an explanation, not to ship nothing. The
# reason is written to $OUT/STATUS and surfaced by bc250-diag.
set -uo pipefail

OUT=${1:-/out}
mkdir -p "$OUT/usr/lib/bc250-gfx1013"
skip() {
	echo "::warning::gfx1013 kernel module skipped: $*"
	echo "not built: $*" > "$OUT/STATUS"
	printf 'not built: %s\n' "$*" > "$OUT/usr/lib/bc250-gfx1013/STATUS"
	exit 0
}

sources=/tmp/bc250-gfx1013

krel=$(rpm -q kernel-core --qf '%{version}-%{release}.%{arch}') || skip 'kernel-core not found'
kver=$(rpm -q kernel-core --qf '%{version}')
krelease=$(rpm -q kernel-core --qf '%{release}')
printf 'base kernel: %s\n' "$krel"

# OpenGamingCollective kernel releases are named ogc3.1.fc44 -> patch tag
# v7.2.9-ogc3 in OpenGamingCollective/linux.
[[ $krelease =~ ^ogc([0-9]+)\.[0-9]+\.fc[0-9]+$ ]] \
	|| skip "unsupported kernel release format '$krelease' (expected ogcN.M.fcXX)"
ogc_tag="v${kver}-ogc${BASH_REMATCH[1]}"

# kernel.org names the first release of a series X.0, later ones X.Y.
tar_kver=$kver
[[ $tar_kver =~ ^([0-9]+\.[0-9]+)\.0$ ]] && tar_kver=${BASH_REMATCH[1]}
major=${kver%%.*}

devel=$(ls /tmp/kernel-rpms/kernel-devel-"${krel}"*.rpm 2>/dev/null | head -1)
[[ -n $devel ]] || skip "kernel-devel for $krel not found in the akmods image"

dnf5 -y install --setopt=install_weak_deps=False \
	gcc make elfutils-libelf-devel openssl xz patch patchutils bc flex bison \
	perl kmod binutils "$devel" >/tmp/dnf-kmod.log 2>&1 \
	|| { tail -20 /tmp/dnf-kmod.log; skip 'installing build dependencies failed'; }

work=/tmp/build/kmod
mkdir -p "$work" && cd "$work" || skip 'workdir'

curl -fsSL --retry 3 -o linux.tar.xz \
	"https://cdn.kernel.org/pub/linux/kernel/v${major}.x/linux-${tar_kver}.tar.xz" \
	|| skip "kernel tarball linux-${tar_kver}.tar.xz not downloadable"
tar xf linux.tar.xz --wildcards "linux-${tar_kver}/drivers/gpu/drm/amd" || skip 'tarball extraction failed'
src="$work/linux-${tar_kver}"

curl -fsSL --retry 3 -o ogc.patch \
	"https://github.com/OpenGamingCollective/linux/releases/download/${ogc_tag}/monolithic.patch" \
	|| skip "OGC patch ${ogc_tag} not downloadable"
filterdiff -p1 -i 'drivers/gpu/drm/amd/*' ogc.patch > ogc-amd.patch
if [[ -s ogc-amd.patch ]]; then
	(cd "$src" && patch -p1 -N -s < "$work/ogc-amd.patch") || skip 'OGC amdgpu changes did not apply'
	printf 'applied OGC amdgpu changes\n'
fi

for p in "$sources"/patches/*.patch; do
	(cd "$src" && patch -p1 -N -s < "$p") || skip "$(basename "$p") did not apply to $kver"
	printf 'applied %s\n' "$(basename "$p")"
done

# The amdgpu trace headers are included relative to the kernel tree, so the
# patched sources have to be visible from there.
kdir="/usr/src/kernels/${krel}"
[[ -d $kdir ]] || skip "kernel build tree $kdir not found"
rm -rf "$kdir/drivers/gpu/drm/amd" && ln -s "$src/drivers/gpu/drm/amd" "$kdir/drivers/gpu/drm/amd"

printf 'building amdgpu.ko\n'
if ! make -C "$kdir" M="$src/drivers/gpu/drm/amd/amdgpu" modules -j"$(nproc)" > "$work/make.log" 2>&1; then
	grep -E 'error|Error' "$work/make.log" | head -30
	skip 'module build failed'
fi
ko="$src/drivers/gpu/drm/amd/amdgpu/amdgpu.ko"
[[ $(modinfo -F vermagic "$ko") == "$krel "* ]] || skip "vermagic mismatch: $(modinfo -F vermagic "$ko")"
[[ $(modinfo -F parm "$ko") == *bc250_gfx1013_v33* ]] || skip 'marker parameter missing from built module'
strip --strip-debug "$ko"

install -D -m 0644 "$ko" "$OUT/usr/lib/bc250-gfx1013/amdgpu.ko"
printf '%s\n' "$krel" > "$OUT/KREL"
printf 'ok kernel=%s ogc=%s size=%s\n' "$krel" "$ogc_tag" "$(du -h "$ko" | cut -f1)" > "$OUT/STATUS"
cp "$OUT/STATUS" "$OUT/usr/lib/bc250-gfx1013/STATUS"
install -m 644 "$sources/LICENSE" "$sources/NOTICE" "$sources/UPSTREAM" \
  "$OUT/usr/lib/bc250-gfx1013/"
cat "$OUT/STATUS"
