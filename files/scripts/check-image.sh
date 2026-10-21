#!/usr/bin/env bash
# Offline image checks: no GPU register writes or service starts during builds.
set -euo pipefail
rpm -q cyan-skillfish-governor-smu pciutils umr
for command in bc250-cu-live-manager bc250-governor-profile cyan-skillfish-governor-smu umr ujust just btrfs swapon zramctl vulkaninfo bc250-async-compute bc250-benchmark mangohud; do
  command -v "$command" >/dev/null
done
for script in /usr/bin/bc250-diag /usr/bin/bc250-memory /usr/bin/bc250-cu-live-manager \
  /usr/bin/bc250-governor-profile \
  /usr/share/bc250-40cu/vendor/bc250-cu-live-manager/bc250-cu-live-manager.sh; do
  test -x "$script"
  bash -n "$script"
done
bc250-cu-live-manager --help >/dev/null
bc250-governor-profile --help >/dev/null
test -s /usr/share/bc250-40cu/UPSTREAM
test -s /usr/share/bc250-40cu/FIXOLAB-LICENSE
(cd /usr/share/bc250-40cu/vendor/bc250-cu-live-manager && sha256sum --check /usr/share/bc250-40cu/SHA256SUMS)
for service in cyan-skillfish-governor-smu.service bc250-force-40cu.service; do
  systemctl --root=/ is-enabled "$service"
done
test -s /usr/lib/modules-load.d/bc250-sensors.conf
test -s /usr/lib/modprobe.d/bc250-sensors.conf
# 40CU sweet spot is the image default (stock governor curve is 24CU-oriented).
test -s /etc/cyan-skillfish-governor-smu/config.toml
grep -q '^max = 1500$' /etc/cyan-skillfish-governor-smu/config.toml
grep -q '^voltage = 900$' /etc/cyan-skillfish-governor-smu/config.toml
# Temperature must come from sysfs, not a long-lived DRM handle: the drm default
# stalls session handovers and drops the HDMI link on DP->HDMI adapters.
grep -q '^temp-read = "sysfs"$' /etc/cyan-skillfish-governor-smu/config.toml
# Safe-points must reach past the shipped cap, or raising [frequency-range].max
# makes the governor error with "beyond max safe point" instead of interpolating.
grep -q '^voltage = 960$' /etc/cyan-skillfish-governor-smu/config.toml
grep -q '^frequency = 2000$' /etc/cyan-skillfish-governor-smu/config.toml
# Split-lock mitigation ships in the image (GDDR6 latency amplifies the penalty).
test -s /usr/lib/sysctl.d/90-bc250-split-lock.conf
grep -q '^kernel.split_lock_mitigate=0$' /usr/lib/sysctl.d/90-bc250-split-lock.conf
# zswap default policy (ZRAM off, swappiness for zswap).
test -s /etc/systemd/zram-generator.conf
test -s /usr/lib/sysctl.d/90-bc250-zswap.conf
grep -q '^vm.swappiness=180$' /usr/lib/sysctl.d/90-bc250-zswap.conf
test -s /usr/lib/dracut/dracut.conf.d/95-bc250-zswap.conf
# e-tho ACPI tables present.
for table in SSDT-CPU.aml SSDT-PST.aml SSDT-STUBS.aml; do
  test -s "/usr/share/bc250-acpi/$table"
done
found_kernel=false
for modules in /usr/lib/modules/*; do
  test -d "$modules" || continue
  found_kernel=true
  modinfo -k "${modules##*/}" -F filename nct6683
done
"$found_kernel"
for recipe in bc250-diagnostics bc250-memory-status bc250-setup-swap bc250-disable-swap \
  bc250-enable-40cu-boot bc250-recover-stock bc250-unlock-logs bc250-cu-status \
  bc250-cu-menu bc250-cu-dry-run-40 bc250-cu-enable-40 \
  bc250-cu-disable-boot bc250-cu-restore-24 bc250-cu-save-boot \
  bc250-cu-sweet-spot bc250-cu-governor-restore \
  bc250-disable-suspend bc250-enable-suspend \
  bc250-async-status bc250-async-test bc250-async-disable bc250-async-enable \
  bc250-benchmark-help bc250-benchmark-list; do
  ujust --show "$recipe" >/dev/null
done
bc250-benchmark --help >/dev/null
for binary in /usr/lib/bc250-radv/lib64/libvulkan_radeon.so \
  /usr/share/bc250-async-compute/test/bc250-ace-test \
  /usr/share/bc250-async-compute/test/bc250-ace-soak; do
  test -f "$binary"
  dependencies=$(ldd "$binary")
  if [[ "$dependencies" == *'not found'* ]]; then
    printf 'Unresolved dependencies for %s:\n%s\n' "$binary" "$dependencies" >&2
    exit 1
  fi
done
test -x /usr/share/bc250-async-compute/test/bc250-ace-test
test -x /usr/share/bc250-async-compute/test/bc250-ace-soak
test -f /usr/share/vulkan/icd.d/radeon_icd.i686.json
test -s /etc/environment.d/95-bc250-async-compute.conf
test -s /etc/pki/containers/bazzite-bc250-stealth-ultra.pub
# Provenance for the vendored patch series and the fetched OGC patches.
test -s /usr/share/bc250-async-compute/UPSTREAM
test -s /usr/share/bc250-async-compute/NOTICE
test -s /usr/share/bc250-async-compute/LICENSE-MIT
test -s /usr/share/bc250-async-compute/LICENSE-GPL-2.0
test -s /usr/share/bc250-async-compute/VERSION
test -s /usr/share/bc250-async-compute/PATCH-SERIES
grep -q '^Mesa ' /usr/share/bc250-async-compute/VERSION
grep -q 'OGC patches: radv-defaults vram-overcommit' /usr/share/bc250-async-compute/VERSION

# The patched amdgpu. Either it is installed and is the module that resolves
# and is the copy in the initramfs, or the build recorded why it is not.
krel=$(rpm -q kernel-core --qf '%{version}-%{release}.%{arch}')
test -s /usr/share/bc250-gfx1013/STATUS
test -s /usr/share/bc250-gfx1013/UPSTREAM
test -s /usr/share/bc250-gfx1013/NOTICE
test -s /usr/share/bc250-gfx1013/LICENSE
if grep -q '^ok ' /usr/share/bc250-gfx1013/STATUS; then
  modinfo -F parm -k "$krel" amdgpu | grep -q bc250_gfx1013_v33
  resolved=$(modinfo -n -k "$krel" amdgpu)
  test -f "$resolved"
  # The initramfs must carry the patched driver, not the stock one: the
  # stock amdgpu is what dracut copies by default, and it is what would
  # load at early boot.
  rm -rf /tmp/bc250-initramfs-check
  mkdir -p /tmp/bc250-initramfs-check
  (cd /tmp/bc250-initramfs-check && lsinitrd --unpack \
    "/usr/lib/modules/$krel/initramfs.img" '*/amdgpu/amdgpu.ko' >/dev/null)
  packed=$(find /tmp/bc250-initramfs-check -name amdgpu.ko -print -quit)
  test -n "$packed"
  grep -q bc250_gfx1013_v33 "$packed"
  rm -rf /tmp/bc250-initramfs-check
else
  # Not built or not installed: the reason must be recorded, and the stock
  # module must still be the one that resolves.
  grep -Eq '^(not built|not installed): ' /usr/share/bc250-gfx1013/STATUS
  ! modinfo -F parm -k "$krel" amdgpu | grep -q bc250_gfx1013_v33
fi
python3 - <<'PY'
import json
import re
from pathlib import Path
environment = Path('/etc/environment').read_text().splitlines()
assignment = re.compile(r'^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=')
for setting in ('AMD_VULKAN_ICD=RADV', 'RADV_DEBUG=nohiz'):
    assert setting in environment, f'Missing graphics default: {setting}'
# zink is retired: it forced KWin and Steam's Chromium through GL-on-Vulkan
# and flickered composited menus. Guard against a silent re-add.
assert not any(assignment.match(line) and assignment.match(line).group(1)
               == 'MESA_LOADER_DRIVER_OVERRIDE' for line in environment), \
    'MESA_LOADER_DRIVER_OVERRIDE must not be set in /etc/environment'
icd = json.loads(Path('/usr/lib/bc250-radv/share/vulkan/icd.d/radeon_icd.x86_64.json').read_text())
assert Path(icd['ICD']['library_path']).is_file()
policy = json.loads(Path('/etc/containers/policy.json').read_text())
docker = policy['transports']['docker']
# The signing module writes a policy entry for this image's own reference.
# The registry part differs between a local build and a CI push (BlueBuild
# uses ghcr.io/<owner> in GitHub Actions and localhost otherwise), so match
# on the image name rather than a hardcoded reference.
entries = {ref: rules for ref, rules in docker.items()
           if ref.endswith('bazzite-bc250-stealth-ultra')}
assert entries, f'no container policy entry for this image: {sorted(docker)}'
assert any(rule['type'] == 'sigstoreSigned'
           for rules in entries.values() for rule in rules), \
    'the container policy entry for this image is not sigstoreSigned'
PY
printf 'BC-250 image health checks passed.\n'
