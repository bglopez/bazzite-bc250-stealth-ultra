#!/usr/bin/env bash
# Verify table integrity and inclusion in each kernel's early initramfs.
# DESTDIR allows the same checks against an isolated test image filesystem.
set -euo pipefail
root="${DESTDIR:-}"
share="$root/usr/share/bc250-acpi"
(cd "$share" && sha256sum --check SHA256SUMS)
python3 - "$share" <<'PY'
from pathlib import Path
import struct
import sys

share = Path(sys.argv[1])
# e-tho/bc250-acpi-fix v1.1.1: SSDT-CPU (idle), SSDT-PST (P-states), SSDT-STUBS (no-op methods).
for name, oem, table_id in [
    ('SSDT-CPU.aml', b'AMD', b'AMD CPU'),
    ('SSDT-PST.aml', b'HACK', b'PSTATES'),
    ('SSDT-STUBS.aml', b'HACK', b'STUBS'),
]:
    data = (share / name).read_bytes()
    assert data[:4] == b'SSDT', f'{name}: not an SSDT'
    assert struct.unpack_from('<I', data, 4)[0] == len(data), f'{name}: invalid length'
    assert sum(data) % 256 == 0, f'{name}: invalid ACPI checksum'
    assert data[10:16].rstrip(b' \0') == oem, f'{name}: unexpected OEM'
    assert data[16:24].rstrip(b' \0') == table_id, f'{name}: unexpected table ID'
PY
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
found_kernel=false
for modules in "$root"/usr/lib/modules/*; do
  test -d "$modules" || continue
  found_kernel=true
  image="$modules/initramfs.img"
  test -s "$image"
  destination="$workdir/${modules##*/}"
  mkdir "$destination"
  # Read only the first, uncompressed CPIO archive. A copy in the main
  # compressed initramfs is too late for the kernel's ACPI table loader.
  (cd "$destination" && cpio --extract --make-directories --quiet \
    --no-absolute-filenames 'kernel/firmware/acpi/*.aml' < "$image")
  for table in SSDT-CPU.aml SSDT-PST.aml SSDT-STUBS.aml; do
    python3 - "$share/$table" "$destination/kernel/firmware/acpi/$table" <<'PY'
from pathlib import Path
import sys
source, packed = map(Path, sys.argv[1:])
assert packed.read_bytes() == source.read_bytes(), f'{packed}: ACPI table mismatch'
PY
  done
done
"$found_kernel"
printf 'BC-250 e-tho ACPI tables verified in all early initramfs archives.\n'
