# Bazzite BC-250

Custom image based directly on [upstream Bazzite Deck](https://github.com/ublue-os/bazzite), with the BC-250 GPU governor, automatic 40CU unlock, diagnostics, and custom system configuration.

**Status: an earlier build was tested on the owner's BC-250. The direct upstream Bazzite rebase still requires an image build and hardware boot/gameplay validation.** The workflow signs each image digest with this repository's cosign key and verifies it before advancing `:latest` (upstream stable) or `:testing` (upstream testing).

## Changes compared with upstream

The direct base is `ghcr.io/ublue-os/bazzite-deck:stable` for `:latest` and `ghcr.io/ublue-os/bazzite-deck:testing` for `:testing`, retaining its kernel, Deck environment, and stock Mesa packages. This repository explicitly installs `cyan-skillfish-governor-smu` from the `filippor/bazzite` COPR, plus `pciutils` and `umr`, and enables the governor service. The runtime 40CU unlock is downloaded directly from [WinnieLV/bc250-cu-live-manager](https://github.com/WinnieLV/bc250-cu-live-manager) at revision `a929085d791f126ce76a60eb609610820fb08066` during the image build and SHA-256 verified before installation. Provenance, checksums, and notices ship in `/usr/share/bc250-40cu`. This repository adds the following configuration and tools:

| Area | Changes in this image |
| --- | --- |
| 40CU dispatch | Enables `bc250-force-40cu.service` to request all 40 CUs on every boot, after GPU initialization and saved CU settings, before the display manager. Adds enable, recovery, and log commands. |
| 40CU governor cap | Applies the community 40CU sweet-spot (`1500 MHz / 900 mV`) as the default `cyan-skillfish-governor-smu` config at image build, because the stock governor curve is 24CU-oriented. `ujust bc250-cu-governor-restore` returns to the package default. |
| Vulkan async compute | Builds Mesa 26.2.5 RADV with three pinned BC-250 patches into `/usr/lib/bc250-radv`. Selects this patched driver globally for 64-bit Vulkan applications in new desktop and game sessions; retains stock 32-bit RADV and software rendering. |
| Graphics session defaults | Sets `AMD_VULKAN_ICD=RADV`, `RADV_DEBUG=nohiz`, and `MESA_LOADER_DRIVER_OVERRIDE=zink` in `/etc/environment`, preserving unrelated base-image settings. |
| Async validation and recovery | Includes correctness and soak tests, queue status, game tracing, and commands to enable or disable global driver selection. |
| Game benchmarks | Adds `bc250-benchmark` for MangoHud frame captures, system context, and before/after comparisons. Driver and unified-heap overrides apply only to the launched game. |
| Temperature monitoring | Loads the base kernel's `nct6683` module with `force=true` at boot for motherboard temperature readings. Does not change fan control. |
| CPU ACPI fix | Includes e-tho `bc250-acpi-fix` v1.1.1 CPU idle/P-state/stub tables in the early initramfs by default; rebuilds and checks the initramfs with each image build. |
| Memory policy | Disables ZRAM and enables **zswap with lz4** (`vm.swappiness=180`), matching community guidance for 16 GB BC-250 boards. Optional disk swapfile remains opt-in. |
| Diagnostics | Adds `bc250-diag` and `ujust bc250-diagnostics` for governor state, clocks, temperatures, kernel arguments, and available driver CU topology. |
| Optional disk swap | Adds `bc250-memory` and `ujust` helpers for an opt-in, persistent 8 GiB Btrfs swapfile at priority 10. No swapfile is allocated by the image build or automatically at boot. |
| Storage maintenance | Explicitly enables `fstrim.timer`; limits persistent journal use to 512 MiB while reserving 1 GiB free through a journald drop-in. |
| CPU mitigations | Adds `mitigations=off` to the deployment's kernel arguments, with the security tradeoff described below. |
| Split-lock mitigation | Sets `kernel.split_lock_mitigate=0` (GDDR6 latency amplifies split-lock penalties on this board). |
| Signed updates | Installs this repository's cosign public key and container policy. CI signs and verifies each digest before promoting it to `:latest` (upstream stable) or `:testing` (upstream testing). |
| Rebuilds and validation | Checks for base-image changes daily at 06:17 UTC and runs offline image checks for required tools, services, sensor support, recipes, Vulkan dependencies, and signing policy. |

The driver and helpers are baked into the image's OSTree-managed `/usr`; they do not require compiling or installing software on the host. Driver-selection defaults ship in `/etc`, where local changes can persist across updates. Optional disk swap is host state in `/var`, created only when requested.

To limit image size, Mesa compilers, development headers, downloaded sources, and build caches stay in the disposable `async-radv` stage; only `/out/usr` is copied into the final image. The private RADV driver is stripped during installation, and the BC-250 package installation skips optional RPM dependencies while retaining required dependencies. Image checks still verify the driver's shared-library dependencies. Actual size savings require a rebuilt-image comparison. Removing files inherited from Bazzite in a later layer alone does not shrink the underlying base layers.

The maintained update tags are `:latest` and `:testing`. The legacy `:test` tag is no longer updated; users following it should switch to `:latest` for upstream stable or `:testing` for upstream testing. The 40CU boot service remains enabled by default, with no manual unlock step required. If you previously masked it for recovery, that local mask persists; run `ujust bc250-enable-40cu-boot` when you want to enable it again.

Governor clocks and voltages are **capped by default to the 40CU sweet spot** (1500 MHz / 900 mV, range 1000–1500), applied at image build via `bc250-governor-profile sweet-spot`. This is intentional: the package's stock curve is a **24CU** profile and can over-drive a board running the unlock. Re-apply with `ujust bc250-cu-sweet-spot`, restore the package default with `ujust bc250-cu-governor-restore`, or edit `/etc/cyan-skillfish-governor-smu/config.toml` for higher clocks (see the 40CU safety table below). Display resolution, refresh rate, game settings, and Steam launch options are not changed by this image. The optional signed-dot-product/FSR4 patch from the async project's documentation is not included; see [FSR4](#fsr4-is-possible-but-not-shipped-here) for the external route. A base-image rebuild does not automatically advance the separately pinned Mesa source version.

## Hardware and BIOS prerequisites

The image cannot fix board-level configuration. Before rebasing, confirm the following against the [BC-250 community guide](https://elektricm.github.io/amd-bc250-docs/):

| Requirement | Why |
| --- | --- |
| BIOS **P2.00–P3.00** or **P5.00** (avoid **P4.00**), **512 MB dynamic VRAM** | Community baseline for working GPU memory behaviour; P5.00 is experimental (EFI-script changes disabled; ReBAR only exists on P5) |
| **IOMMU disabled** | IOMMU is broken on this board and causes display failures |
| Clear CMOS after any BIOS flash, then reapply VRAM settings | Missing CMOS clear causes freezes while loading levels in newer games |
| **Never run Smokeless_UMAF** | Can permanently damage the board |
| Keep the **4 nylon washers** under the heatsink screws | Missing washers → 90–100 °C idle |
| PSU with **300 W+ on the 12 V rail** (400 W+ if overclocking), 8-pin PCIe | Stock gaming draws 150–235 W; 40CU and overclocks go higher. Single 8-pin is only safe to ~260 W at the wall — 40CU/OC builds often need the board's Micro-Fit supplemental power. Never use SATA→8-pin or 6-pin→8-pin adapters; 8-pin connectors can melt past ~250 W. Use 16 AWG pure-copper wire |
| High-static-pressure 120 mm fan and airflow over the backplate VRAM | Backplate GDDR6 has no temp sensor and overheats silently |
| Expect a **30–60 s black screen early in boot** | Display output initializes late; the system is still booting |

Kernel note: community guidance is to avoid known-bad kernel series for gfx1013 (6.15.0–6.15.6 and 6.17.8–6.17.10; see the guide's kernel support matrix). Prefer 6.19.x / 6.18 LTS / current Bazzite 44+ kernels. This image inherits whatever kernel the selected upstream Bazzite channel ships — check `uname -r` after update. Historical community reports that "Bazzite stable is too old for 40CU" referred to older 6.17.7 builds; Bazzite 44-era kernels are in wide use, but if you see green screens or freezes with 40CU, consider rebasing to `bazzite-deck:testing` or disabling the unlock.

If you later unlock CPU cores (8-core unlock is a separate, riskier mod), this image's ACPI tables and metrics still assume the stock 6-core/12-thread CPU — see the [unofficial community guide](https://github.com/katzzero/bc250-unofficial-community-guide) before mixing unlocks.

## Build

The [GitHub Actions workflow](.github/workflows/build.yml) builds the BlueBuild recipe on pushes to `master` that change non-Markdown files, or when manually dispatched. Both channels use the same recipe and customizations, with independently signed and verified images:

| Upstream base | Published image |
| --- | --- |
| `ghcr.io/ublue-os/bazzite-deck:stable` | `ghcr.io/bglopez/bazzite-bc250-stealth-ultra:latest` |
| `ghcr.io/ublue-os/bazzite-deck:testing` | `ghcr.io/bglopez/bazzite-bc250-stealth-ultra:testing` |

The legacy `:test` tag is no longer published. A failure in one channel does not cancel the other channel's build.

Check [Actions](https://github.com/bglopez/bazzite-bc250-stealth-ultra/actions) for a successful run and [Packages](https://github.com/bglopez?tab=packages) for the published image before continuing. A green workflow does not guarantee the image boots or works correctly on your hardware.

The workflow also checks both upstream Bazzite Deck channels daily at 06:17 UTC. Scheduled runs rebuild each channel only when its upstream digest differs from that channel's last successful publication, or when its cached record is unavailable. Pushes and manual runs always build both channels. The record is updated only after signing, verification, and tag promotion succeed. This publishes an available update; it does not reboot or update your host automatically.

Build-time health checks require the CU manager, governor, sensor kernel module, enabled boot services, custom helpers, and image signing policy. These checks run offline without starting services or writing GPU registers.

## Maintenance helpers

The image extends Bazzite's `ujust` commands with the vendored BC-250 helpers:

| Command | Purpose |
| --- | --- |
| `ujust bc250-diagnostics` | Read-only hardware and temperature report |
| `ujust bc250-memory-status` | RAM, ZRAM, disk swap, and memory pressure |
| `ujust bc250-setup-swap` | Create or re-enable an optional 8 GiB disk swapfile |
| `ujust bc250-disable-swap` | Disable disk swap while retaining its file |
| `ujust bc250-enable-40cu-boot` | Enable automatic full dispatch and apply it now |
| `ujust bc250-recover-stock` | Disable both boot unlock paths and restore driver dispatch |
| `ujust bc250-unlock-logs` | Show automatic unlock logs for this boot |
| `ujust bc250-cu-status` | Privileged live SPI/WGP dispatch table (needs sudo) |
| `ujust bc250-cu-menu` | Interactive CU manager menu |
| `ujust bc250-cu-dry-run-40` | Preview a full 40CU enable without writing registers |
| `ujust bc250-cu-enable-40` | Enable full 40CU dispatch for this boot only |
| `ujust bc250-cu-save-boot` | Save the current table and install the upstream boot service (second unlock path) |
| `ujust bc250-cu-disable-boot` | Remove the upstream saved-table boot service only |
| `ujust bc250-cu-restore-24` | Restore the stock dispatch table (live) |
| `ujust bc250-cu-sweet-spot` | Re-apply the 40CU governor profile (1500 MHz / 900 mV; image default) |
| `ujust bc250-cu-governor-restore` | Restore the pre-sweet-spot governor config |
| `ujust bc250-disable-suspend` | Mask system suspend/hibernate targets (opt-in) |
| `ujust bc250-enable-suspend` | Unmask suspend/hibernate targets |
| `ujust bc250-async-status` | Compare stock and patched Vulkan queue availability |
| `ujust bc250-async-test` | Run async compute correctness tests |
| `ujust bc250-async-disable` | Select stock Vulkan drivers for the next session |
| `ujust bc250-async-enable` | Select patched Vulkan globally for the next session |
| `ujust bc250-benchmark-help` | Show game benchmark capture options |
| `ujust bc250-benchmark-list` | List saved benchmark runs |

`bc250-recover-stock` restores CU dispatch only; use `bc250-async-disable` separately to restore stock Vulkan selection. `bc250-cu-disable-boot` removes only the upstream saved-table service; the image's `bc250-force-40cu.service` is a separate path and stays enabled unless masked.

### Optional disk swap

The image preserves Bazzite's memory-management stack except for the zswap policy above. The optional helper creates `/var/lib/bc250swap/swapfile` in its own Btrfs subvolume, with an 8 GiB default size and swap priority 10 (below zswap's preferred paging). It requires enough space to leave at least 10 GiB free. No swapfile is created automatically at boot.

Run `ujust bc250-setup-swap` to activate it persistently. For a different size on first setup, use `sudo bc250-memory setup 16` (1–32 GiB supported). Repeating setup with the same size reuses the file; existing files are not resized or overwritten. `ujust bc250-disable-swap` disables it immediately and for future boots, keeping the file for reuse. This is additional swap capacity, not hibernation configuration.

Use `ujust bc250-memory-status` during a demanding game to assess memory pressure before changing memory settings.

### Memory policy notes (ZRAM vs swapfile)

This image **disables ZRAM and enables zswap** (`zswap.enabled=1 zswap.max_pool_percent=25 zswap.compressor=lz4`, `vm.swappiness=180`), matching community guidance for 16 GB boards (for example [NexGen3D's SteamMachine scripts](https://github.com/NexGen-3D-Printing/SteamMachine)): ZRAM plus 512 MB dynamic VRAM has been linked to crashes in memory-heavy games, and zswap+lz4 is generally faster here. A disk swapfile is still optional (`ujust bc250-setup-swap`) for extra capacity.

To return to stock Bazzite ZRAM behavior, replace `/etc/systemd/zram-generator.conf` and remove `vm.swappiness` from `/etc/sysctl.d/90-bc250-zswap.conf`, then drop the `zswap.*` kernel arguments with `rpm-ostree kargs`.

## Image signing

GitHub Actions requires two repository secrets: `SIGNING_SECRET` (the encrypted private key) and `COSIGN_PASSWORD` (its password). Only `cosign.pub` belongs in Git.

Builds upload a unique staging tag first, sign and verify its immutable digest, then promote that same digest to `:latest` for upstream stable or `:testing` for upstream testing. A signing or verification failure prevents promotion. Staging images can exist unsigned and should not be used for deployment. Signatures use the legacy attachment format for OSTree/container-policy compatibility.

## Switching from stock Bazzite Deck

Start from stock **Bazzite Deck (KDE)** on your BC-250. These instructions use `rpm-ostree`; keep the same desktop environment when switching images. See [Bazzite's rebase guide](https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/rebase_guide/) for background. If your deployment is managed by bootc, use its switching workflow instead.

First, confirm a successful publication in [Actions](https://github.com/bglopez/bazzite-bc250-stealth-ultra/actions). From a trusted checkout of this repository, verify the image with its public key:

```bash
cosign verify --key cosign.pub ghcr.io/bglopez/bazzite-bc250-stealth-ultra:latest
```

Record your current deployment, then perform the initial rebase:

```bash
rpm-ostree status
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/bglopez/bazzite-bc250-stealth-ultra:latest
sudo systemctl reboot
```

The initial rebase uses an unverified registry reference because stock Bazzite does not yet trust this image's signing key. The image installs the key and signing policy. After rebooting into it, switch to the signed reference so subsequent updates enforce signature verification:

```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/bglopez/bazzite-bc250-stealth-ultra:latest
sudo systemctl reboot
```

### Verify after reboot

```bash
rpm-ostree status
systemctl status cyan-skillfish-governor-smu bc250-force-40cu.service --no-pager
ujust bc250-cu-status
ujust bc250-async-test
```

Full 40CU dispatch is enabled by default; no manual unlock step is needed. Look for `CUs active & routed : 40/40` in the CU status output.

## Rollback and return to stock Bazzite

To return to the previous deployment:

```bash
sudo rpm-ostree rollback
sudo systemctl reboot
```

Check `rpm-ostree status` first: after the second rebase, the previous deployment may also be this custom image. To explicitly return to stock Bazzite Deck stable:

```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ublue-os/bazzite-deck:stable
sudo systemctl reboot
```

If the system does not boot, select a working previous deployment from the bootloader.

## Notes

- Stay on the **Deck (KDE)** variant when following these instructions.
- `:latest` and `:testing` are mutable tags tracking their respective upstream channels; consider pinning a tested image digest for reproducibility.
- This project is independent of Bazzite.
- Further reading: [elektricM BC-250 docs](https://elektricm.github.io/amd-bc250-docs/), [katzzero unofficial community guide](https://github.com/katzzero/bc250-unofficial-community-guide), [NexGen3D SteamMachine](https://github.com/NexGen-3D-Printing/SteamMachine), [62fixolab patched images](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images).
- Not carried in this image (community projects, evaluate separately): DirectMesh, HelixSR/OptiScaler upscaler, Vulkan_NullVRS, `bc250-metrics-fix-bazzite` (8-core only), 8-core unlocks, BIOS mods.

## BC-250 40CU base and CPU mitigations

This custom image uses `ghcr.io/ublue-os/bazzite-deck:stable` and includes the runtime CU manager directly. It **enables full 40CU dispatch by default at every boot** through `bc250-force-40cu.service`. No manual enable command or saved CU profile is required on a fresh installation. An existing local service mask remains respected across upgrades. It runs `bc250-cu-live-manager --yes enable all` after GPU initialization and any saved upstream CU profile, before the display manager. Sustained 40CU at high clocks will throttle on stock cooling. This image therefore **caps the governor at the community thermal guidance by default** — a **1500 MHz / 900 mV** operating point (`[frequency-range] min = 1000`, `max = 1500`). That config is applied at image build; the package default is backed up under `/etc/cyan-skillfish-governor-smu/backups/`.

To re-apply or tune:

```bash
ujust bc250-cu-sweet-spot        # re-apply 1500 MHz / 900 mV
ujust bc250-cu-governor-restore  # return to the backed-up package default
```

Editing `/etc/cyan-skillfish-governor-smu/config.toml` is supported; restart with `sudo systemctl restart cyan-skillfish-governor-smu`. Voltage curves are board-specific; see the [governor guide](https://elektricm.github.io/amd-bc250-docs/system/governor/) before raising clocks past 2000 MHz. Consult the [pinned upstream manager guide](https://github.com/WinnieLV/bc250-cu-live-manager/blob/a929085d791f126ce76a60eb609610820fb08066/README.md) for status interpretation and recovery.

#### Raising the clock cap

The governor interpolates voltage between `[[safe-points]]` and refuses any frequency beyond its outermost point — it raises a `tried to set a frequency beyond max safe point` error rather than silently clamping. This image's sweet-spot profile therefore ships a curve out to **2000 MHz** while keeping `[frequency-range] max = 1500`, so the extra points stay inert until you raise the cap. To tune:

```bash
sudo sed -i 's/^max = 1500/max = 2000/' /etc/cyan-skillfish-governor-smu/config.toml
sudo systemctl restart cyan-skillfish-governor-smu
```

Values up to `max = 2000` need no other edit. **Above 2000 MHz you must add your own `[[safe-points]]` entry first**, or the governor will error on every adjustment. Note the shipped curve is *conservative* relative to the table below; treat community voltage figures as a ceiling to approach, not a target to hit.

**40CU safety envelope (community field data):**

| Clock | Voltage | Notes |
| --- | --- | --- |
| 1500 MHz | 900 mV | Image default sustained 40CU point (`bc250-cu-sweet-spot`) |
| 1600–1850 MHz | 910–930 mV | Shipped safe-points; interpolation headroom, not a recommendation |
| 2000 MHz | 960 mV shipped (~980–1000 mV reported) | Safe daily ceiling for most boards on good air |
| 2200 MHz | ~1030–1050 mV | Practical 40CU wall before secondary power limits |
| 2400 MHz | any | **OCP hard lock** — board powers off rails, needs cable pull |

Never set governor voltage below **700 mV** (locks the GPU at 1500 MHz or crashes at start). A **500 MHz floor can black-screen at idle** on some boards — this image's sweet-spot profile keeps `[frequency-range] min = 1000` for that reason. The stock governor curve is a **24CU** profile: do not run 40CU at the package defaults under sustained load. Games often need +10–15 mV more than synthetic tests. CPU overclocking lowers the GPU power trip point — undervolt the CPU if you push GPU clocks.

**CU count caveats:** the two shader engines run symmetrically, so only 24/28/32/36/40 CU counts are meaningful (an "38 CU" config is really 36). `amdgpu.disable_cu=` indexes **WGP pairs** (`SE.SH.WGP`), not individual CUs. After a live unlock, `amdgpu_gca_config` can still show 24 — verify with `ujust bc250-cu-status` or `RADV_DEBUG=info vulkaninfo --summary | grep num_cu`. On Bazzite the DRM node is often `card1`/`dri` index 1. Bad CUs may only fail under RT or long sessions (Doom: The Dark Ages / CS2 are sensitive); use the live manager's per-WGP disable to bisect, and restore stock dispatch (`ujust bc250-recover-stock`) if games crash while compute tests pass.

### FSR4 is possible, but not shipped here

The board's native `v_dot4_i32_i8` path is broken on gfx1013 — upstream Mesa still excludes `CHIP_GFX1013` from `has_accelerated_dot_product` — and direct testing returns `0` where the correct result is `70`. That part has not changed. **What has changed is the workaround**: [dmorazasanchez/bc250-fsr4](https://github.com/dmorazasanchez/bc250-fsr4) V3 makes FSR 4 usable by leaving the native signed packed-dot instruction *disabled* and instead lowering the operation in software via a deferred-SDot optimization round, removing the catastrophic VGPR spill/scratch behaviour the fallback otherwise causes (256→168 VGPR, 1314→0 spills on the worst-captured shader). The maintainer reports ~58→63 FPS on one Cyberpunk 2077 development scene with FSR 4.1.1 INT8 and frame generation off. Treat that as a single-scene figure, not a general result.

This image **does not include it**, and the signed-dot-product patch from the async project's documentation is likewise not included. That patch targets the native path, which is the one that is broken. Adopting the external route means installing a second private RADV alongside `/usr/lib/bc250-radv` and selecting it per-game via `VK_DRIVER_FILES`; the two drivers are not validated together here. Measure on your own board before relying on it.

If you evaluate it, keep it per-game rather than system-wide, exactly as `bc250-benchmark --driver stock|patched` does for driver comparisons.

The unlock revision is pinned in `files/system/usr/share/bc250-40cu/vendor/bc250-cu-live-manager.UPSTREAM_REF`, with file hashes in `files/system/usr/share/bc250-40cu/SHA256SUMS`. Update both when intentionally upgrading the manager. Downloads happen only during image builds; boot-time unlocking works offline. The separate `duggasco/bc250-40cu-unlock` kernel-patch/research bundle is not required by this runtime service.

Verify after reboot:

```bash
systemctl status bc250-force-40cu.service --no-pager
ujust bc250-cu-status
```

Look for `CUs active & routed : 40/40`; the driver's initialization count can still show 24 CUs.

To disable automatic full dispatch and restore the stock dispatch table:

```bash
sudo systemctl mask --now bc250-force-40cu.service
ujust bc250-cu-disable-boot
ujust bc250-cu-restore-24
```

The mask persists across image updates. To enable it again, run `ujust bc250-enable-40cu-boot` (unmasks, enables, and applies now) or `sudo systemctl unmask bc250-force-40cu.service` and reboot. If the image fails to boot, select the previous deployment from the bootloader.

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

These defaults take effect after deploying the rebuilt image and starting a new session (or rebooting). Existing local edits to `/etc/environment` can persist across image updates; check the active values with `printenv AMD_VULKAN_ICD RADV_DEBUG MESA_LOADER_DRIVER_OVERRIDE VK_DRIVER_FILES`. Applications can override them individually, and Flatpak graphics behavior still needs separate validation.

Driver selection is split across three places:

| File | Role |
| --- | --- |
| `/etc/environment` | `AMD_VULKAN_ICD`, `RADV_DEBUG=nohiz`, `MESA_LOADER_DRIVER_OVERRIDE=zink` |
| `/etc/environment.d/95-bc250-async-compute.conf` | `VK_DRIVER_FILES` / `VK_ICD_FILENAMES` → patched 64-bit RADV, stock 32-bit RADV, software `lvp` |
| `/etc/profile.d/95-bc250-async-compute.sh` | Same ICD chain for login shells |

`ujust bc250-async-disable` / `ujust bc250-async-enable` rewrite the environment.d/profile.d files; the three `/etc/environment` graphics defaults are left alone. `bc250-async-compute steam` prints the recommended per-game Steam launch options; `bc250-async-compute env` shows the session selection; `bc250-async-compute always status` reports whether the patched driver is the system default.

The image builds a private Mesa 26.2.5 RADV with the three patches from [bc250-async-compute-bazzite](https://github.com/tri3gubki-ops/bc250-async-compute-bazzite), pinned to commit `56bf06b986f4639c32a669e9cdd31cdf7fba44b6`. Mesa's source archive is SHA-256 checked. The patches were dry-run against the 26.2.5 tarball and apply with small offsets. The build stage's compilers and headers are not copied into the final image.

The patched 64-bit driver lives at `/usr/lib/bc250-radv` and is selected globally for new graphical sessions and login shells. Stock Mesa remains installed, including its 32-bit driver. Current system game profiles are used through drirc symlinks. The optional signed-dot-product patch is not included; see [FSR4](#fsr4-is-possible-but-not-shipped-here).

This exposes the BC-250's dedicated compute queue. Performance gains depend on the game actually using that queue; queue availability and passing correctness tests do not establish higher FPS. Flatpak applications have separate graphics runtimes and are not validated by this integration.

Historical validation of an earlier image build on the owner's BC-250 with kernel `7.2.9-ogc2.1.fc44.x86_64`: the locally built driver exposed four dedicated compute queues, passed all five correctness tests, and completed a 60-second soak with 272 rounds and 356 million verified words. GPU temperature stayed at 62–63 °C during that test. After deployment and reboot, the installed driver also passed all five correctness tests, and the owner confirmed that games work with the updated image. These checks establish functionality; no FPS improvement has been measured for Cyberpunk 2077, Luma Island, or SMITE 2. Other community builds of the gfx1013 compute-queue patch report larger gains in some titles (for example ~+20–25% in Cyberpunk at 1440p on 40CU) — measure on your board with `bc250-benchmark`.

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

This image does **not** enable the unified RADV memory heap globally: community reports say `radv_enable_unified_heap_on_apu` can break VRAM reporting in some games. Measure per title instead:

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

## CPU ACPI fix (e-tho v1.1.1)

The image includes `SSDT-CPU.aml`, `SSDT-PST.aml`, and `SSDT-STUBS.aml` from [e-tho/bc250-acpi-fix](https://github.com/e-tho/bc250-acpi-fix) tag `v1.1.1` (MIT). That release replaces the earlier bc250-collective tables and stubs undefined firmware methods. Note the direction on the **C3 idle state**: an earlier commit published it, then it was **reverted** because it caused system freezes — the firmware reporting C3 as unsupported was correct. `v1.1.1` re-points at the post-revert commit, so C3 is deliberately absent; this image's tables publish POLL/C1/C2 only. The tables cover all 16 firmware CPU definitions; stock boards use the first 12 logical processors (`P000`–`P00B`). They provide ACPI definitions for CPU idle states and frequency scaling (800 MHz–3.2 GHz). They are usable on an 8-core unlock as well, but this image does not ship 8-core tooling. The separate 40CU GPU unlock remains enabled.

Tables, source files, checksums, and provenance live in `/usr/share/bc250-acpi`. The dracut configuration at `/usr/lib/dracut/dracut.conf.d/95-bc250-acpi.conf` enables early ACPI table loading. BlueBuild regenerates the image's initramfs, and build checks verify the exact tables are present in its uncompressed early archive for every installed kernel. No manual bootloader edits or host-side `rpm-ostree initramfs --enable` step are required for a normal deployment of the image. If a modded BIOS already injects ACPI fixes, disable one side to avoid duplicate tables.

After updating and rebooting, verify the running system:

```bash
sudo journalctl -k -b | grep -Ei 'ACPI.*(SSDT|override|upgrade)|lockdown'
cat /sys/devices/system/cpu/cpu0/cpuidle/state*/name
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
```

Build checks establish packaging, not runtime support or power savings. The original upstream README reports incomplete support, while the [newer BC-250 guide](https://elektricm.github.io/amd-bc250-docs/system/governor/#acpi-fix-installation) reports working C/P-states on a newer kernel. Confirm behavior on your BIOS and kernel; Secure Boot/lockdown may prevent ACPI overrides. CPU governor selection remains under Bazzite's power-management policy. If the updated image causes boot or stability problems, boot a previous deployment without these tables and roll back.

## Motherboard temperature sensors


The image loads `nct6683` at boot with `force=true`, following the [BC-250 sensor guide](https://elektricm.github.io/amd-bc250-docs/system/sensors/). This enables read-only motherboard monitoring; it does not configure fan control.

After installing the updated image and rebooting, run `bc250-diag` and check the thermal sensor section for motherboard readings (reported as `nct6686` on the owner's board). If readings are missing, check:

```bash
lsmod | grep nct6683
sudo journalctl -k -b | grep -i nct6683
```

The defaults are in `/usr/lib/modules-load.d/bc250-sensors.conf` and `/usr/lib/modprobe.d/bc250-sensors.conf`. To disable them locally, mask both files with same-named symlinks to `/dev/null` in `/etc/modules-load.d/` and `/etc/modprobe.d/`, then reboot.

For **PWM fan control** (not included), the community uses the out-of-tree `nct6687` driver instead of `nct6683`, often with `ujust install-coolercontrol` for fan curves. Do not load both modules at once. See the [sensors guide](https://elektricm.github.io/amd-bc250-docs/system/sensors/).

## Read-only BC-250 diagnostics

On this image, run `bc250-diag` as a regular user. It prints the governor service state, BC-250 GPU clock levels (or readable hwmon frequency values), thermal sensor readings, the running kernel command line, and KFD driver-reported CU topology when available. A `*` in the GPU SCLK table marks the current level. You can save the report with `bc250-diag > bc250-report.txt`.

The helper tolerates missing devices and sensors and never changes clocks, CU settings, or services. KFD topology describes what the driver initialized; it does **not** confirm the live 40CU SPI/WGP dispatch table. The upstream `bc250-cu-live-manager status` uses privileged register access, so this helper does not invoke it or prompt for `sudo`. This image requests full 40CU dispatch at boot; use `ujust bc250-cu-status` to verify the live result.

## Known issues and community fixes

Board quirks the image cannot fix, plus host-side workarounds from the BC-250 community ([elektricM guide](https://elektricm.github.io/amd-bc250-docs/), [unofficial community guide](https://github.com/katzzero/bc250-unofficial-community-guide), [62fixolab](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images)):

| Symptom | What to do |
| --- | --- |
| Deck UI micro-stutter every few seconds | HHD fail-loops on BC-250. Mask it: `sudo systemctl disable --now hhd && sudo systemctl mask hhd` |
| Box dead after sitting idle (no wake, only power cycle) | S3/S4 sleep does not work on this SMU. Run `ujust bc250-disable-suspend`, and disable Gamescope/Game Mode idle suspend separately |
| GPU stuck at 1500 MHz | Governor not running, or voltage below 700 mV locks the clock. `systemctl status cyan-skillfish-governor-smu`; check `pp_dpm_sclk` on **both** `card0` and `card1`. If you raised `[frequency-range] max`, also check `journalctl -u cyan-skillfish-governor-smu` for `beyond max safe point` — see [Raising the clock cap](#raising-the-clock-cap) |
| Graphics artifacts / black squares | `RADV_DEBUG=nohiz` is already global; for stubborn cases try `RADV_DEBUG=aco AMD_DEBUG=aco %command%` per game |
| Flatpak games use software rendering | Flatpak ships its own Mesa runtime — the private patched RADV is not used there |
| Game Mode / D3D12 crashes (Steam restart loop) | Launch with `-dx11` (confirmed on several titles); same games often fine from desktop |
| Sunshine crashes (`status=139`) or black screen after Bazzite 44 | `ujust setup-sunshine`, then set `encoder = software` and `capture = kms` in `~/.config/sunshine/sunshine.conf` |
| MangoHud frame-time sawtooth / 655% usage | Disable MangoHud for pacing issues; 655% is a BC-250 metrics bug (governor `fix-metrics = true` helps) |
| VRAM reported lower than expected | Known RADV visibility limit. Do **not** enable `radv_enable_unified_heap_on_apu` globally — it breaks VRAM reporting in some games (e.g. TLOU) and can stop others launching. Use `bc250-benchmark --heap on/off` per game. `Failed to pin framebuffer … -12` = under-allocated VRAM |
| Games crash mid-scene at 512 MB dynamic VRAM | Try a 6 GB fixed BIOS split for AAA titles that need a large VRAM window (some titles are the reverse — measure) |
| Memory-heavy games crash | See [Memory policy notes](#memory-policy-notes-zram-vs-swapfile) |
| No hardware video encode/decode | VCN is power-gated / unusable publicly; use software encode (x264) in OBS etc. |
| Pitch-shifted or missing DP→HDMI audio | Prefer native DisplayPort; passive adapters only; USB DAC as fallback. This image sets governor `temp-read = "sysfs"` so the governor does not hold a DRM handle that stalls handovers; DP audio itself needs kernel 6.19.10+ |
| TV flicker / handshake via adapter dongles | Use a plain DP→HDMI **cable** (no dongle). BIOS needs native DP. Adapters that drop the link when the picture is blank benefit from the `temp-read = "sysfs"` default shipped here |
| Unstable CPU overclock / random reboots | Never exceed **1.325 V CPU core (Vid)** — bricking risk. GPU governor min voltage must stay ≥ 700 mV |
| Hard power-off under load (rails dead, wall <30 W) | OCP trip — lower GPU clocks (≤2200 MHz), stay within the 40CU voltage table, reduce CPU OC. Single 8-pin is only safe to ~260 W wall |
| Intermittent no-POST / aging VRAM | Community workaround: cap GPU memory clock 1750 → 1650 MHz (~5% bandwidth cost) |
| 40CU crashes in games but compute is fine | Silicon lottery. Mask suspect WGPs or restore stock dispatch (`ujust bc250-recover-stock`); see duggasco's per-WGP health test |
| `ujust update` re-downloads / fails on Bazzite 44 | Known loop report involving the skillfish governor layer. Update from Desktop Mode (not Game Mode), then reinstall/restart the governor if needed |
| WiFi dongle stops working after rebase | Custom images can drop out-of-tree drivers. Prefer in-kernel chipsets (MT7921AU etc.); `rpm-ostree rollback` if needed |
| Green screens / crashes at idle after a governor tune | Raise the lowest safe-point voltage (board-dependent; some need ≥760 mV at 350–500 MHz). Never leave min voltage <700 mV |

Related reading: [Bazzite setup](https://elektricm.github.io/amd-bc250-docs/linux/bazzite/), [governor tuning](https://elektricm.github.io/amd-bc250-docs/system/governor/), [40CU unlock](https://elektricm.github.io/amd-bc250-docs/system/40cu-unlock/), [troubleshooting](https://elektricm.github.io/amd-bc250-docs/troubleshooting/display/).
