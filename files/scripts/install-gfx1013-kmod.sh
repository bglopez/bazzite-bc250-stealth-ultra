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
#
# A degraded install still has to ship: the image builds with the stock
# kernel and an explanation rather than failing. Every failure path records
# the reason in STATUS, leaves the stock module as the one that loads (a
# replacement that fails verification is rolled back, so STATUS can never
# contradict the live driver), keeps the staged module for on-device
# diagnosis, and prints the details to the build log.
set -euo pipefail

trap 'printf "install-gfx1013-kmod.sh failed at line %d: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

share=/usr/share/bc250-gfx1013
staged=/usr/lib/bc250-gfx1013
install -d "$share"

# The provenance of the patch series ships whatever the outcome: the image
# checks require it unconditionally, and it documents the series the image
# was (or was not) built with.
for file in LICENSE NOTICE UPSTREAM; do
	if [[ -f $staged/$file ]]; then
		install -m 644 "$staged/$file" "$share/$file"
	fi
done

krel=$(rpm -q kernel-core --qf '%{version}-%{release}.%{arch}')
module=$staged/amdgpu.ko
stock=/usr/lib/modules/${krel}/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko
backup=/tmp/bc250-amdgpu-stock.bak

record() { printf '%s\n' "$1" > "$share/STATUS"; cat "$share/STATUS"; }

# Failure-path detail for the build log. STATUS stays a one-line
# machine-readable reason; everything else goes to stderr.
diagnose() {
	{
		printf 'krel=%s\n' "$krel"
		ls -la "$staged" 2>&1
		md5sum "$module" "$stock" 2>&1
		printf 'resolved=%s\n' "$(modinfo -n -k "$krel" amdgpu 2>&1)"
		printf 'staged marker count: %s\n' \
			"$(modinfo -F parm "$module" 2>/dev/null | grep -c bc250_gfx1013_v33)"
		printf 'live marker count: %s\n' \
			"$(modinfo -F parm -k "$krel" amdgpu 2>/dev/null | grep -c bc250_gfx1013_v33)"
	} >&2
}

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
	diagnose
	exit 0
fi

# The marker is checked on the staged file before the stock module is
# touched: whatever the build stage verified, only the bytes about to be
# written matter here, and they must never go over the stock driver
# without the marker.
if ! modinfo -F parm "$module" | grep -q bc250_gfx1013_v33; then
	record 'not installed: the staged module lacks the bc250_gfx1013_v33 marker'
	diagnose
	exit 0
fi

rollback=
if [[ -f $stock ]]; then
	cp -p "$stock" "$backup"
	rollback=restore
	cat "$module" > "$stock"
	chmod 0755 "$stock"
else
	# No stock module at the expected path: fall back to updates/, which
	# modprobe prefers over the kernel tree.
	install -D -m 0644 "$module" "/usr/lib/modules/${krel}/updates/amdgpu.ko"
	rollback=remove
fi
depmod -a "$krel"

# Put the tree back the way it was so a failed verification cannot leave
# the image with a driver its STATUS does not describe.
undo() {
	case $rollback in
	restore)
		cat "$backup" > "$stock"
		chmod 0755 "$stock"
		;;
	remove)
		rm -f "/usr/lib/modules/${krel}/updates/amdgpu.ko"
		;;
	esac
	depmod -a "$krel"
	rm -f "$backup"
}

resolved=$(modinfo -n -k "$krel" amdgpu)
if [[ $resolved != *amdgpu.ko ]]; then
	undo
	record "not installed: modprobe does not resolve amdgpu ($resolved)"
	diagnose
	exit 0
fi
if ! modinfo -F parm -k "$krel" amdgpu | grep -q bc250_gfx1013_v33; then
	undo
	record 'not installed: the module in use is not the patched one'
	diagnose
	exit 0
fi
rm -f "$backup"

# The staged copy is only needed until the module is in place; keeping it
# would put another 45 MB of driver in the image.
rm -f "$module" "$staged/STATUS"
record "ok kernel=$krel module=$resolved"
