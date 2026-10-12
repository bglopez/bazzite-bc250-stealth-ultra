# Bazzite BC-250

Custom Bazzite Deck image derived from [62fixolab's BC-250 patched 40CU Deck image](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images), with BC-250 diagnostics and custom system configuration.

**Status: tested on the owner's BC-250, including successful boot, async compute correctness tests, and owner-confirmed gameplay.** The workflow signs each image digest with this repository's cosign key and verifies it before advancing `:test` and `:latest`. The upstream 62fixolab signature does **not** automatically sign this derived image.

## Changes compared with upstream

The direct base remains `ghcr.io/62fixolab/bazzite-bc250-patched-deck-40cu:latest`. Its Bazzite Deck environment, patched kernel, GPU governor, stock Mesa packages, CU manager, and existing `ujust` recipes are inherited. This repository adds the following configuration and tools:

| Area | Changes in this image |
| --- | --- |
| 40CU dispatch | Enables `bc250-force-40cu.service` to request all 40 CUs on every boot, after GPU initialization and saved CU settings, before the display manager. Adds enable, recovery, and log commands. |
| Vulkan async compute | Builds Mesa 26.2.4 RADV with three pinned BC-250 patches into `/usr/lib/bc250-radv`. Selects this patched driver globally for 64-bit Vulkan applications in new desktop and game sessions; retains stock 32-bit RADV and software rendering. |
| Graphics session defaults | Sets `AMD_VULKAN_ICD=RADV`, `RADV_DEBUG=nohiz`, and `MESA_LOADER_DRIVER_OVERRIDE=zink` in `/etc/environment`, preserving unrelated base-image settings. |
| Vulkan memory heap | Enables `radv_enable_unified_heap_on_apu` through an immutable RADV drirc profile, presenting shared APU memory as one device-local heap. |
| Async validation and recovery | Includes correctness and soak tests, queue status, game tracing, and commands to enable or disable global driver selection. |
| Game benchmarks | Adds `bc250-benchmark` for MangoHud frame captures, system context, and before/after comparisons. Driver and unified-heap overrides apply only to the launched game. |
| Temperature monitoring | Loads the base kernel's `nct6683` module with `force=true` at boot for motherboard temperature readings. Does not change fan control. |
| Diagnostics | Adds `bc250-diag` and `ujust bc250-diagnostics` for governor state, clocks, temperatures, kernel arguments, and available driver CU topology. |
| Optional disk swap | Adds `bc250-memory` and `ujust` helpers for an opt-in, persistent 8 GiB Btrfs swapfile at priority 10. No swapfile is allocated by the image build or automatically at boot. |
| Storage maintenance | Explicitly enables `fstrim.timer`; limits persistent journal use to 512 MiB while reserving 1 GiB free through a journald drop-in. |
| CPU mitigations | Adds `mitigations=off` to the deployment's kernel arguments, with the security tradeoff described below. |
| Signed updates | Installs this repository's cosign public key and container policy. CI signs and verifies each digest before promoting it to both `:test` and `:latest`. |
| Rebuilds and validation | Checks for base-image changes daily at 06:17 UTC and runs offline image checks for required tools, services, sensor support, recipes, Vulkan dependencies, and signing policy. |

The driver and helpers are baked into the image's OSTree-managed `/usr`; they do not require compiling or installing software on the host. Driver-selection defaults ship in `/etc`, where local changes can persist across updates. Optional disk swap is host state in `/var`, created only when requested.

Governor clocks and voltages, Bazzite's ZRAM defaults, display resolution, refresh rate, game settings, and Steam launch options are not changed by this image. The optional signed-dot-product/FSR4 patch from the async project's documentation is not included. A base-image rebuild does not automatically advance the separately pinned Mesa source version.

## Build

The [GitHub Actions workflow](.github/workflows/build.yml) builds the BlueBuild recipe on pushes to `master` that change non-Markdown files, or when manually dispatched. Successful builds publish the same verified digest to both tags:

```text
ghcr.io/bglopez/bazzite-bc250-stealth-ultra:test
ghcr.io/bglopez/bazzite-bc250-stealth-ultra:latest
```

Check [Actions](https://github.com/bglopez/bazzite-bc250-stealth-ultra/actions) for a successful run and [Packages](https://github.com/bglopez?tab=packages) for the published image before continuing. A green workflow does not guarantee the image boots or works correctly on your hardware.

The workflow also checks the 62fixolab 40CU base daily at 06:17 UTC. Scheduled runs rebuild only when its digest differs from the last successful publication, or when that cached record is unavailable. Pushes and manual runs always build. The record is updated only after signing, verification, and tag promotion succeed. This publishes an available update; it does not reboot or update your host automatically.

Build-time health checks require the CU manager, governor, sensor kernel module, enabled boot services, custom helpers, and image signing policy. These checks run offline without starting services or writing GPU registers.

## Maintenance helpers

The image extends Bazzite's `ujust` commands while retaining upstream's existing BC-250 helpers:

| Command | Purpose |
| --- | --- |
| `ujust bc250-diagnostics` | Read-only hardware and temperature report |
| `ujust bc250-memory-status` | RAM, ZRAM, disk swap, and memory pressure |
| `ujust bc250-setup-swap` | Create or re-enable an optional 8 GiB disk swapfile |
| `ujust bc250-disable-swap` | Disable disk swap while retaining its file |
| `ujust bc250-enable-40cu-boot` | Enable automatic full dispatch and apply it now |
| `ujust bc250-recover-stock` | Disable both boot unlock paths and restore driver dispatch |
| `ujust bc250-unlock-logs` | Show automatic unlock logs for this boot |
| `ujust bc250-async-status` | Compare stock and patched Vulkan queue availability |
| `ujust bc250-async-test` | Run async compute correctness tests |
| `ujust bc250-async-disable` | Select stock Vulkan drivers for the next session |
| `ujust bc250-async-enable` | Select patched Vulkan globally for the next session |
| `ujust bc250-benchmark-help` | Show game benchmark capture options |
| `ujust bc250-benchmark-list` | List saved benchmark runs |

`bc250-recover-stock` restores CU dispatch only; use `bc250-async-disable` separately to restore stock Vulkan selection.

### Optional disk swap

The image preserves Bazzite's ZRAM and memory-management defaults. The optional helper creates `/var/lib/bc250swap/swapfile` in its own Btrfs subvolume, with an 8 GiB default size and swap priority 10 (below this host's ZRAM priority 100). It requires enough space to leave at least 10 GiB free. No swapfile is created automatically at boot.

Run `ujust bc250-setup-swap` to activate it persistently. For a different size on first setup, use `sudo bc250-memory setup 16` (1–32 GiB supported). Repeating setup with the same size reuses the file; existing files are not resized or overwritten. `ujust bc250-disable-swap` disables it immediately and for future boots, keeping the file for reuse. This is additional swap capacity, not hibernation configuration.

Use `ujust bc250-memory-status` during a demanding game to assess memory pressure before changing memory settings.

## Image signing

GitHub Actions requires two repository secrets: `SIGNING_SECRET` (the encrypted private key) and `COSIGN_PASSWORD` (its password). Only `cosign.pub` belongs in Git.

Builds upload a unique staging tag first, sign and verify its immutable digest, then promote that same digest to `:test` and `:latest`. A signing or verification failure prevents promotion. Staging images can exist unsigned and should not be used for deployment. Signatures use the legacy attachment format for OSTree/container-policy compatibility.

## Switching from 62fixolab's BC-250 Deck image

The original image uses a signed OSTree ref:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest
```

The recipe installs this repository's public key and signing policy for subsequent signed updates. Your existing deployment must trust that key before a signed rebase will work. For the initial switch to a **successfully built, published, and verified** image, the unverified-registry OCI rebase syntax is:

```bash
# Record the currently deployed image and available rollback deployment
rpm-ostree status

# Only after confirming a successful build and verifying the image signature
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/bglopez/bazzite-bc250-stealth-ultra:test
sudo systemctl reboot
```

This uses an **unverified registry image** and therefore does not enforce image signature verification. Verify the registry signature first using the public key from a trusted checkout of this repository:

```bash
cosign verify --key cosign.pub ghcr.io/bglopez/bazzite-bc250-stealth-ultra:test
```

If the deployment is managed by bootc, use `bootc status` and follow the bootc-compatible switching workflow for that installation instead of assuming both interfaces are interchangeable.

### Verify after reboot

```bash
rpm-ostree status
uname -r
systemctl status cyan-skillfish-governor-smu --no-pager
```

## Rollback and return to the original image

If the new deployment boots but has problems, return to the previous deployment:

```bash
sudo rpm-ostree rollback
sudo systemctl reboot
```

Or explicitly return to the original signed 62fixolab Deck image (assuming its signing policy is still installed and trusted):

```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest
sudo systemctl reboot
```

If the system does not boot, select the previous deployment from the bootloader rather than attempting commands in the broken deployment.

## Notes

- Stay on the **Deck** variant; do not switch desktop environments as part of this test.
- The custom `:test` tag is mutable; consider pinning a tested image digest for reproducibility.
- This project is independent of Bazzite and 62fixolab.

See [62fixolab's installation guide](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images#install) and [Bazzite's rebase guide](https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/rebase_guide/) for additional background.


## BC-250 40CU base and CPU mitigations

This custom image inherits from `ghcr.io/62fixolab/bazzite-bc250-patched-deck-40cu:latest`. Unlike the upstream image's optional unlock, this custom image **enables full 40CU dispatch at every boot** through `bc250-force-40cu.service`, for the owner's already-tested board. It runs `bc250-cu-live-manager --yes enable all` after GPU initialization and any saved upstream CU profile, before the display manager. It does not change governor clocks or voltage. Consult the [upstream 40CU guide](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images/blob/main/docs/40cu.md) for status interpretation and recovery.

Verify after reboot:

```bash
systemctl status bc250-force-40cu.service --no-pager
ujust bc250-cu-status
```

Look for `SPI total : 40/40 CUs`; the driver's initialization count can still show 24 CUs.

To disable automatic full dispatch and restore the stock dispatch table:

```bash
sudo systemctl mask --now bc250-force-40cu.service
ujust bc250-cu-disable-boot
ujust bc250-cu-restore-24
```

The mask persists across image updates. To enable it again, run `sudo systemctl unmask bc250-force-40cu.service` and reboot. If the image fails to boot, select the previous deployment from the bootloader.

### CPU vulnerability mitigations

**Security warning:** `mitigations=off` disables CPU security mitigations. It is not a universal gaming performance improvement and may expose the system to additional attack classes. Use only if you accept the risk.

The current BlueBuild recipe includes `mitigations=off` in its kernel arguments. This is already part of the image configuration; no separate command is needed to add it.

Verify after reboot:

```bash
cat /proc/cmdline
```

To remove it from future builds, delete the `mitigations=off` entry in `recipes/recipe.yml` and rebuild. Kernel arguments are deployment-specific, so check the running command line after reboot.

Keep a known-good deployment available for rollback. This image's automatic 40CU setting is intended for the owner's tested board; stability is not guaranteed on other boards.

## Async compute Vulkan driver

The image includes the [BC-250 guide's system-wide graphics settings](https://elektricm.github.io/amd-bc250-docs/drivers/radv/#system-wide-configuration) in `/etc/environment`: `AMD_VULKAN_ICD=RADV`, `RADV_DEBUG=nohiz`, and `MESA_LOADER_DRIVER_OVERRIDE=zink`. These request RADV, disable hierarchical Z, and select Zink for OpenGL. They leave the private Vulkan ICD selection intact and do not add `nocompute`, which would disable the patched compute queue.

These defaults take effect after deploying the rebuilt image and starting a new session (or rebooting). Existing local edits to `/etc/environment` can persist across image updates; check the active values with `printenv AMD_VULKAN_ICD RADV_DEBUG MESA_LOADER_DRIVER_OVERRIDE`. Applications can override them individually, and Flatpak graphics behavior still needs separate validation.

The image builds a private Mesa 26.2.4 RADV with the three patches from [bc250-async-compute-bazzite](https://github.com/tri3gubki-ops/bc250-async-compute-bazzite), pinned to commit `56bf06b986f4639c32a669e9cdd31cdf7fba44b6`. Mesa's source archive is SHA-256 checked. The build stage's compilers and headers are not copied into the final image.

The patched 64-bit driver lives at `/usr/lib/bc250-radv` and is selected globally for new graphical sessions and login shells. Stock Mesa remains installed, including its 32-bit driver. Current system game profiles are used through drirc symlinks. The optional signed-dot-product/FSR4 patch is not included.

The image installs `/usr/share/drirc.d/99-bc250-unified-heap.conf` with `radv_enable_unified_heap_on_apu=true`. Both the private RADV and system RADV can read this profile. It presents shared APU memory as one device-local Vulkan heap instead of splitting it into device-local and system heaps. This can help games that make allocation decisions based on reported VRAM; it does not increase physical memory or guarantee higher FPS. Existing `/etc/drirc`, user profiles, or environment overrides can take precedence. Restart applications after deployment to pick up the setting. To compare or disable it for one Steam game, use `radv_enable_unified_heap_on_apu=false %command%`. Flatpak runtimes need separate validation.

This exposes the BC-250's dedicated compute queue. Performance gains depend on the game actually using that queue; queue availability and passing correctness tests do not establish higher FPS. Flatpak applications have separate graphics runtimes and are not validated by this integration.

Hardware validation on the owner's BC-250 with kernel `7.2.9-ogc2.1.fc44.x86_64`: the locally built driver exposed four dedicated compute queues, passed all five correctness tests, and completed a 60-second soak with 272 rounds and 356 million verified words. GPU temperature stayed at 62–63 °C during that test. After deployment and reboot, the installed driver also passed all five correctness tests, and the owner confirmed that games work with the updated image. These checks establish functionality; no FPS improvement has been measured for Cyberpunk 2077, Luma Island, or SMITE 2.

After updating and rebooting:

```bash
ujust bc250-async-status
ujust bc250-async-test
# Optional sustained correctness test (seconds):
bc250-async-compute soak 300
```

To return globally to stock Mesa, run `ujust bc250-async-disable`, then log out and back in or reboot. Re-enable with `ujust bc250-async-enable` followed by a new session. If the desktop fails, use a text console (Ctrl+Alt+F3) to run the disable command, or boot the previous deployment.

For a game-specific stock-driver comparison, use Steam launch options:

```text
env -u VK_DRIVER_FILES -u VK_ICD_FILENAMES %command%
```

To record whether a game uses compute queues, use `bc250-game-trace %command%`, then inspect `bc250-async-compute trace`. Trace logging adds overhead; compare performance separately with tracing disabled.

## Before/after game benchmarks

`bc250-benchmark` wraps a game with MangoHud and saves per-frame CSV data plus
the kernel, image deployment, driver settings, governor configuration and memory
settings. It requires no sudo and changes no persistent performance settings.

For a unified-heap comparison, use this Steam launch option for the first run:

```text
bc250-benchmark run heap-off --heap off -- %command%
```

Warm up the game, enter a repeatable scene, then press **Left Shift+F2**. Capture
stops after 60 seconds; the game stays open. Exit normally, then repeat with:

```text
bc250-benchmark run heap-on --heap on -- %command%
```

Compare from a terminal:

```bash
bc250-benchmark compare heap-off heap-on
bc250-benchmark list
```

Results include average FPS, 1% low FPS, p99 frame time, frames over 50 ms per
minute, and available clock, temperature, load and memory readings. The 1% low
is the reciprocal of the mean of the slowest 1% of frame times. Higher FPS is
better; lower frame times and fewer long frames are better.

Use the same scene, resolution, graphics settings, upscaler, frame generation,
Proton version and frame cap. Repeat each configuration at least three times;
small differences may be normal run-to-run variation. `--notes "..."` records
these details, and `--seconds 120` changes capture length. `--delay 30` starts
logging automatically 30 seconds after each application's overlay initializes;
manual capture is preferable for excluding menus and loading screens.

To compare system RADV with the bundled patched RADV, use `--driver stock` and
`--driver patched`, keeping the heap setting identical. This compares the two
Mesa builds, not just the async patch; 32-bit games continue using stock RADV.
Omitting these flags uses the current environment. Driver flags record the
requested selection; a launcher or sandbox can override or hide the host driver
and MangoHud layer. Check that the overlay appears.

Runs are stored in `~/.local/share/bc250-benchmarks` (or under `XDG_DATA_HOME`),
including `run.json`, `summary.json`, the raw CSVs and the capture configuration.
Set `BC250_BENCHMARK_DIR` to choose another location. Labels resolve to their
latest run; pass full run paths from `list` to compare older repetitions.
`bc250-benchmark report LABEL` regenerates a report. If a launcher or repeated
capture produces multiple CSVs, comparison requires selecting them explicitly:

```bash
bc250-benchmark compare heap-off heap-on --before-csv GAME_BEFORE.csv --after-csv GAME_AFTER.csv
```

The helper uses its own MangoHud configuration, replacing any personal MangoHud
overlay settings and MangoHud FPS limit for the launched game. In-game and
Gamescope limits still apply. Use the helper for both sides of a comparison.
It cannot reconstruct measurements from before installation; heap and driver
overrides let you record fresh comparisons without changing system defaults.

## Motherboard temperature sensors


The image loads `nct6683` at boot with `force=true`, following [62fixolab's temperature sensor configuration](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images#temperature-sensors). This enables read-only motherboard monitoring; it does not configure fan control.

After installing the updated image and rebooting, run `bc250-diag` and check the thermal sensor section for motherboard readings (reported as `nct6686` on the owner's board). If readings are missing, check:

```bash
lsmod | grep nct6683
sudo journalctl -k -b | grep -i nct6683
```

The defaults are in `/usr/lib/modules-load.d/bc250-sensors.conf` and `/usr/lib/modprobe.d/bc250-sensors.conf`. To disable them locally, mask both files with same-named symlinks to `/dev/null` in `/etc/modules-load.d/` and `/etc/modprobe.d/`, then reboot.

## Read-only BC-250 diagnostics

On this image, run `bc250-diag` as a regular user. It prints the governor service state, BC-250 GPU clock levels (or readable hwmon frequency values), thermal sensor readings, the running kernel command line, and KFD driver-reported CU topology when available. A `*` in the GPU SCLK table marks the current level. You can save the report with `bc250-diag > bc250-report.txt`.

The helper tolerates missing devices and sensors and never changes clocks, CU settings, or services. KFD topology describes what the driver initialized; it does **not** confirm the live 40CU SPI/WGP dispatch table. The upstream `bc250-cu-live-manager status` uses privileged register access, so this helper does not invoke it or prompt for `sudo`. This image requests full 40CU dispatch at boot; use `ujust bc250-cu-status` to verify the live result.
