#!/usr/bin/env bash
# Offline image checks: no GPU register writes or service starts during builds.
set -euo pipefail
for command in bc250-cu-live-manager bc250-governor-profile cyan-skillfish-governor-smu umr ujust just btrfs swapon zramctl; do
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
  bc250-enable-40cu-boot bc250-recover-stock bc250-unlock-logs bc250-cu-status; do
  ujust --show "$recipe" >/dev/null
done
test -s /etc/pki/containers/bazzite-bc250-stealth-ultra.pub
python3 - <<'PY'
import json
from pathlib import Path
policy = json.loads(Path('/etc/containers/policy.json').read_text())
rules = policy['transports']['docker']['ghcr.io/bglopez/bazzite-bc250-stealth-ultra']
assert any(rule['type'] == 'sigstoreSigned' for rule in rules)
PY
printf 'BC-250 image health checks passed.\n'
