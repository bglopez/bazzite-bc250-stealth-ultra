#!/usr/bin/env bash
# Offline image checks: no GPU register writes or service starts during builds.
set -euo pipefail
for command in bc250-cu-live-manager bc250-governor-profile cyan-skillfish-governor-smu umr ujust just btrfs swapon zramctl vulkaninfo bc250-async-compute bc250-benchmark mangohud; do
  command -v "$command" >/dev/null
done
for script in /usr/bin/bc250-diag /usr/bin/bc250-memory /usr/bin/bc250-cu-live-manager \
  /usr/share/bc250-40cu/vendor/bc250-cu-live-manager/bc250-cu-live-manager.sh; do
  test -x "$script"
  bash -n "$script"
done
for service in cyan-skillfish-governor-smu.service bc250-force-40cu.service; do
  systemctl --root=/ is-enabled "$service"
done
test -s /usr/lib/modules-load.d/bc250-sensors.conf
test -s /usr/lib/modprobe.d/bc250-sensors.conf
found_kernel=false
for modules in /usr/lib/modules/*; do
  test -d "$modules" || continue
  found_kernel=true
  modinfo -k "${modules##*/}" -F filename nct6683
done
"$found_kernel"
for recipe in bc250-diagnostics bc250-memory-status bc250-setup-swap bc250-disable-swap \
  bc250-enable-40cu-boot bc250-recover-stock bc250-unlock-logs bc250-cu-status \
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
python3 - <<'PY'
import json
from pathlib import Path
import xml.etree.ElementTree as ET

profile = Path('/usr/share/drirc.d/99-bc250-unified-heap.conf')
root = ET.parse(profile).getroot()
option = root.find("./device[@driver='radv']/application/option[@name='radv_enable_unified_heap_on_apu']")
assert option is not None and option.get('value') == 'true', 'Missing unified APU heap default'
assert Path('/usr/lib/bc250-radv/share/drirc.d').resolve() == profile.parent
environment = Path('/etc/environment').read_text().splitlines()
for setting in ('AMD_VULKAN_ICD=RADV', 'RADV_DEBUG=nohiz', 'MESA_LOADER_DRIVER_OVERRIDE=zink'):
    assert setting in environment, f'Missing graphics default: {setting}'
icd = json.loads(Path('/usr/lib/bc250-radv/share/vulkan/icd.d/radeon_icd.x86_64.json').read_text())
assert Path(icd['ICD']['library_path']).is_file()
policy = json.loads(Path('/etc/containers/policy.json').read_text())
rules = policy['transports']['docker']['ghcr.io/bglopez/bazzite-bc250-stealth-ultra']
assert any(rule['type'] == 'sigstoreSigned' for rule in rules)
PY
printf 'BC-250 image health checks passed.\n'
