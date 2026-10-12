#!/usr/bin/env bash
# Bake session-wide graphics defaults into the image without replacing unrelated settings.
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import re

path = Path('/etc/environment')
defaults = {
    'AMD_VULKAN_ICD': 'RADV',
    'RADV_DEBUG': 'nohiz',
    'MESA_LOADER_DRIVER_OVERRIDE': 'zink',
}
lines = path.read_text().splitlines() if path.exists() else []
assignment = re.compile(r'^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=')
lines = [line for line in lines
         if not ((match := assignment.match(line)) and match[1] in defaults)]
lines.extend(f'{key}={value}' for key, value in defaults.items())
path.write_text('\n'.join(lines) + '\n')
PY
