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
}
# MESA_LOADER_DRIVER_OVERRIDE=zink is deliberately no longer set. In
# /etc/environment it applied session-wide, not just to games, so it also
# forced KWin and Steam's Chromium GPU process through OpenGL-on-Vulkan on
# top of the patched RADV. Composited popups and window moves flickered as a
# result. It is listed here so an earlier deployment's line is actively
# stripped: /etc is mutable across image updates, so simply stopping to write
# the key would leave it in place on machines that already have it.
retired = ('MESA_LOADER_DRIVER_OVERRIDE',)
lines = path.read_text().splitlines() if path.exists() else []
assignment = re.compile(r'^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=')
lines = [line for line in lines
         if not ((match := assignment.match(line))
                 and (match[1] in defaults or match[1] in retired))]
lines.extend(f'{key}={value}' for key, value in defaults.items())
path.write_text('\n'.join(lines) + '\n')
PY
