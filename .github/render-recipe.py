#!/usr/bin/env python3
"""Render recipes/recipe.yml for one upstream channel and base kernel.

Three things in the recipe have to track the upstream channel, and none of
them can be resolved while the recipe is being written:

  - image-version / alt-tags select the upstream Bazzite channel.
  - the two build stages start FROM the base image, because the private
    RADV is built at the base image's own Mesa version and the amdgpu module
    is built against the base image's own kernel.
  - the akmods image that provides kernel-devel for the base kernel. Its
    tag carries the base kernel's release, which only the base image's
    ostree.linux label knows.

The rendered recipe is what the build actually uses. The checked-in recipe
is the stable-channel rendering and stays buildable on its own.
"""
import argparse
import re
import sys
from pathlib import Path

RECIPE = Path("recipes/recipe.yml")


def fedora_major(kernel_release: str) -> str:
    match = re.search(r"\.fc(\d+)\.", kernel_release)
    if not match:
        raise SystemExit(f"unexpected kernel release format: {kernel_release}")
    return match.group(1)


def render(channel: str, kernel_release: str, staging_tag: str) -> str:
    text = RECIPE.read_text()
    major = fedora_major(kernel_release)

    text = re.sub(
        r"^image-version: .*$",
        f"image-version: {channel}",
        text,
        count=1,
        flags=re.M,
    )
    text = re.sub(
        r"^alt-tags: \[.*\]$",
        f"alt-tags: [{staging_tag}]",
        text,
        count=1,
        flags=re.M,
    )
    text = re.sub(
        r"^(\s*from: ghcr\.io/ublue-os/bazzite-deck:)\S+$",
        rf"\g<1>{channel}",
        text,
        flags=re.M,
    )
    text = re.sub(
        r"^(\s*from: ghcr\.io/ublue-os/akmods:)ogc-\d+-\S+$",
        rf"\g<1>ogc-{major}-{kernel_release}",
        text,
        flags=re.M,
    )

    if f"bazzite-deck:{channel}" not in text:
        raise SystemExit(f"no base image stage was rendered for channel {channel}")
    if f"akmods:ogc-{major}-{kernel_release}" not in text:
        raise SystemExit(f"no akmods image was rendered for kernel {kernel_release}")
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--channel", required=True, help="upstream Bazzite channel")
    parser.add_argument("--kernel-release", required=True, help="base image ostree.linux label")
    parser.add_argument("--staging-tag", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    if not re.search(r"\.fc\d+\.", args.kernel_release):
        print(f"unexpected kernel release format: {args.kernel_release}", file=sys.stderr)
        return 1
    print(f"base image kernel: {args.kernel_release} (Fedora {fedora_major(args.kernel_release)})")

    rendered = render(args.channel, args.kernel_release, args.staging_tag)
    Path(args.output).write_text(rendered)
    print(f"rendered {args.output} for channel {args.channel}, kernel {args.kernel_release}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
