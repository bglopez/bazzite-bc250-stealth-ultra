# Bazzite BC-250 Stealth Ultra (experimental)

Custom Bazzite Deck image derived from [62fixolab's BC-250 patched Deck image](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images), adding an experimental [xonedo](https://github.com/honjow/xonedo) driver build for the Turtle Beach Stealth Ultra 2.4 GHz USB receiver.

**Status: experimental. Do not rebase until the GitHub Actions build succeeds, the GHCR image exists, and the driver and bootc/OSTree compatibility have been verified.** The current workflow publishes a `:test` image without configuring this repository's own cosign signing policy. The upstream 62fixolab signature does **not** automatically sign this derived image.

## Build

The [GitHub Actions workflow](.github/workflows/build.yml) builds on pushes to `master`, resolving the current upstream `honjow/xonedo` HEAD for each build. Successful builds are intended to publish:

```text
ghcr.io/bglopez/bazzite-bc250-stealth-ultra:test
```

Check [Actions](https://github.com/bglopez/bazzite-bc250-stealth-ultra/actions) for a successful run and [Packages](https://github.com/bglopez?tab=packages) for the published image before continuing. A green workflow does not guarantee the image boots or the dongle works.

## Switching from 62fixolab's BC-250 Deck image

The original image uses a signed OSTree ref:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest
```

**Do not use `ostree-image-signed:` for this custom image yet:** this repository has not configured its own signing key and verification policy. If you decide to test a **successfully built, published, and verified** image, the unsigned/experimental OCI rebase syntax is:

```bash
# Record the currently deployed image and available rollback deployment
rpm-ostree status

# EXPERIMENTAL: only after confirming a successful image build and bootc compatibility
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/bglopez/bazzite-bc250-stealth-ultra:test
sudo systemctl reboot
```

This uses an **unverified registry image** and therefore does not enforce image signature verification. Prefer configuring cosign signing and a matching verification policy before using the image as a daily driver. If the deployment is managed by bootc, use `bootc status` and follow the bootc-compatible switching workflow for that installation instead of assuming both interfaces are interchangeable.

### Verify after reboot

```bash
rpm-ostree status
uname -r
lsusb -d 10f5:7070
lsmod | grep -E 'xone|gip' || true
sudo dmesg | grep -iE 'xone|gip|10f5' | tail -n 60
systemctl status cyan-skillfish-governor-smu --no-pager
```

The USB ID should be checked against your actual dongle; module names and driver support depend on the upstream revision.

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
- Kernel modules must match the kernel ABI inside the image. An unsuccessful module build or missing firmware means this is not a deployable controller fix.
- This project is independent of Bazzite and 62fixolab.

See [62fixolab's installation guide](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images#install) and [Bazzite's rebase guide](https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/rebase_guide/) for additional background.


## BC-250 40CU base and CPU mitigations

This custom image now inherits from `ghcr.io/62fixolab/bazzite-bc250-patched-deck-40cu:latest`. The upstream 40CU image includes **optional runtime unlock tooling**, not a guaranteed or automatically enabled 40CU mode. Consult the [upstream 40CU guide](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images/blob/main/docs/40cu.md) for board-specific enablement and recovery.

### Optional: disable CPU vulnerability mitigations

**Security warning:** `mitigations=off` disables CPU security mitigations. It is not a universal gaming performance improvement and may expose the system to additional attack classes. Use only if you accept the risk.

Kernel arguments are deployment-specific and are **not automatically changed by the container recipe**. To opt in after confirming your new deployment boots, run:

```bash
sudo rpm-ostree kargs --append-if-missing=mitigations=off
sudo systemctl reboot
```

Verify after reboot:

```bash
cat /proc/cmdline
```

To undo the setting:

```bash
sudo rpm-ostree kargs --delete-if-present=mitigations=off
sudo systemctl reboot
```

Keep a known-good deployment available for rollback. Do not enable additional compute units until you've confirmed stability at your current setting.
