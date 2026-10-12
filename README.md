# Bazzite BC-250 (experimental)

Custom Bazzite Deck image derived from [62fixolab's BC-250 patched 40CU Deck image](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images), with BC-250 diagnostics and custom system configuration.

**Status: experimental. Do not rebase until the GitHub Actions build succeeds, the GHCR image exists, and bootc/OSTree compatibility has been verified.** The workflow signs each image digest with this repository's cosign key and verifies it before advancing `:test` and `:latest`. The upstream 62fixolab signature does **not** automatically sign this derived image.

## Build

The [GitHub Actions workflow](.github/workflows/build.yml) builds the BlueBuild recipe on pushes to `master` that change non-Markdown files, or when manually dispatched. Successful builds are intended to publish:

```text
ghcr.io/bglopez/bazzite-bc250-stealth-ultra:test
```

Check [Actions](https://github.com/bglopez/bazzite-bc250-stealth-ultra/actions) for a successful run and [Packages](https://github.com/bglopez?tab=packages) for the published image before continuing. A green workflow does not guarantee the image boots or works correctly on your hardware.

## Image signing

GitHub Actions requires two repository secrets: `SIGNING_SECRET` (the encrypted private key) and `COSIGN_PASSWORD` (its password). Only `cosign.pub` belongs in Git.

Builds upload a unique staging tag first, sign and verify its immutable digest, then promote that same digest to `:test` and `:latest`. A signing or verification failure prevents promotion. Staging images can exist unsigned and should not be used for deployment. Signatures use the legacy attachment format for OSTree/container-policy compatibility.

## Switching from 62fixolab's BC-250 Deck image

The original image uses a signed OSTree ref:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest
```

The recipe installs this repository's public key and signing policy for subsequent signed updates. Your existing deployment must trust that key before a signed rebase will work. For the initial switch to a **successfully built, published, and verified** image, the unsigned/experimental OCI rebase syntax is:

```bash
# Record the currently deployed image and available rollback deployment
rpm-ostree status

# EXPERIMENTAL: only after confirming a successful image build and bootc compatibility
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

This custom image now inherits from `ghcr.io/62fixolab/bazzite-bc250-patched-deck-40cu:latest`. The upstream 40CU image includes **optional runtime unlock tooling**, not a guaranteed or automatically enabled 40CU mode. Consult the [upstream 40CU guide](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images/blob/main/docs/40cu.md) for board-specific enablement and recovery.

### CPU vulnerability mitigations

**Security warning:** `mitigations=off` disables CPU security mitigations. It is not a universal gaming performance improvement and may expose the system to additional attack classes. Use only if you accept the risk.

The current BlueBuild recipe includes `mitigations=off` in its kernel arguments. This is already part of the image configuration; no separate command is needed to add it.

Verify after reboot:

```bash
cat /proc/cmdline
```

To remove it from future builds, delete the `mitigations=off` entry in `recipes/recipe.yml` and rebuild. Kernel arguments are deployment-specific, so check the running command line after reboot.

Keep a known-good deployment available for rollback. Do not enable additional compute units until you've confirmed stability at your current setting.

## Motherboard temperature sensors

The image loads `nct6683` at boot with `force=true`, following [62fixolab's temperature sensor configuration](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images#temperature-sensors). This enables read-only motherboard monitoring; it does not configure fan control.

After installing the updated image and rebooting, run `bc250-diag` and check the thermal sensor section for `nct6683` readings. If readings are missing, check:

```bash
lsmod | grep nct6683
sudo journalctl -k -b | grep -i nct6683
```

The defaults are in `/usr/lib/modules-load.d/bc250-sensors.conf` and `/usr/lib/modprobe.d/bc250-sensors.conf`. To disable them locally, mask both files with same-named symlinks to `/dev/null` in `/etc/modules-load.d/` and `/etc/modprobe.d/`, then reboot.

## Read-only BC-250 diagnostics

On this image, run `bc250-diag` as a regular user. It prints the governor service state, BC-250 GPU clock levels (or readable hwmon frequency values), thermal sensor readings, the running kernel command line, and KFD driver-reported CU topology when available. A `*` in the GPU SCLK table marks the current level. You can save the report with `bc250-diag > bc250-report.txt`.

The helper tolerates missing devices and sensors and never changes clocks, CU settings, or services. KFD topology describes what the driver initialized; it does **not** confirm the live 40CU SPI/WGP dispatch table. The upstream `bc250-cu-live-manager status` uses privileged register access, so this helper does not invoke it or prompt for `sudo`. The 40CU image includes optional tooling for up to 40 CUs, but that does not mean 40 CUs are active or stable on a particular board.
