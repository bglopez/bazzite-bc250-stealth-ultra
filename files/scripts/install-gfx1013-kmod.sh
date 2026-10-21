#!/usr/bin/env bash
# Install the patched amdgpu into the image and make it the module that loads.
#
# The module replaces the stock one in place rather than being added under
# updates/. Both work, but dracut's no-hostonly pass copies the whole GPU
# module set into the initramfs, so a module added under updates/ ends up
# next to the stock one rather than replacing it: the initramfs then carries
# two copies of a 45 MB driver and depends on modules.dep to pick the right
# one. Replacing in place leaves exactly one amdgpu.ko, in the initramfs and
# in the image, and it is the patched one.
set -euo pipefail

share=/usr/share/bc250-gfx1013
staged=/usr/lib/bc250-gfx1013
install -d "$share"

krel=$(rpm -q kernel-core --qf '%{version}-%{release}.%{arch}')
module=$staged/amdgpu.ko
stock=/usr/lib/modules/${krel}/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko

record() { printf '%s\n' "$1" > "$share/STATUS"; cat "$share/STATUS"; }

if [[ ! -f $module ]]; then
	# The build stage explains why. Carry that reason over rather than
	# inventing one.
	reason='not built: the build stage produced no patched amdgpu'
	if [[ -r $staged/STATUS ]]; then
		reason="not built: $(sed -e 's/^skipped: //' -e 's/^not built: //' "$staged/STATUS")"
	fi
	record "$reason"
	exit 0
fi

# A module built for another kernel must never be installed: it would not
# load, and a half-applied driver swap is worse than none.
vermagic=$(modinfo -F vermagic "$module")
if [[ $vermagic != "$krel "* ]]; then
	record "not installed: module vermagic $vermagic does not match $krel"
	exit 0
fi

if [[ -f $stock ]]; then
	cat "$module" > "$stock"
	chmod 0755 "$stock"
else
	# No stock module at the expected path: fall back to updates/, which
	# modprobe prefers over the kernel tree.
	install -D -m 0644 "$module" "/usr/lib/modules/${krel}/updates/amdgpu.ko"
fi
depmod -a "$krel"

resolved=$(modinfo -n -k "$krel" amdgpu)
if [[ $resolved != *amdgpu.ko ]]; then
	record "not installed: modprobe does not resolve amdgpu ($resolved)"
	exit 0
fi
if ! modinfo -F parm -k "$krel" amdgpu | grep -q bc250_gfx1013_v33; then
	record 'not installed: the module in use is not the patched one'
	exit 0
fi

for file in LICENSE NOTICE UPSTREAM; do
	[[ -f $staged/$file ]] && install -m 644 "$staged/$file" "$share/$file"
done
# The staged copy is only needed until the module is in place; keeping it
# would put another 45 MB of driver in the image.
rm -f "$module" "$staged/STATUS"
record "ok kernel=$krel module=$resolved"
