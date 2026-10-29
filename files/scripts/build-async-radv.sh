#!/usr/bin/env bash
# Build the private BC-250 RADV in a disposable stage.
#
# The driver is built at the *base image's own* Mesa version and with the
# base image's OpenGamingCollective patches applied, so the private driver
# stays in step with the Mesa Bazzite ships instead of forking off on a
# separately pinned tarball. When the base image moves to a new Mesa, this
# follows it.
#
# Patch order matters. The vendored BC-250 series is applied first, then the
# OGC patches: OGC's vram-overcommit patch inserts into radv_amdgpu_bo.c at
# the same place DirectMesh's first hunk expects the pristine file, so the
# reverse order conflicts.
#
# The vendored series is keyed by the Mesa release it was rebased for. The
# base image's Mesa moves on its own schedule, and a series rebased for one
# release does not apply to the next, so the series that matches the base
# image's Mesa is selected here and a base image with no matching series
# fails the build rather than shipping a driver that silently diverges.
set -euo pipefail

sources=/tmp/bc250-async
prefix=/usr/lib/bc250-radv
share=/out/usr/share/bc250-async-compute
ogc_base=https://raw.githubusercontent.com/OpenGamingCollective/mesa/refs/tags

# Mesa version of the base image this stage is built from.
mesa_version=$(rpm -q --qf '%{version}' mesa-vulkan-drivers.x86_64)
[[ $mesa_version =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || {
	printf 'unexpected Mesa version from the base image: %s\n' "$mesa_version" >&2
	exit 1
}
printf 'base image Mesa: %s\n' "$mesa_version"

# Select the vendored series for this Mesa release: an exact version match
# first, then the series for the whole minor release.
series=
for candidate in "$sources/patches/$mesa_version" "$sources/patches/${mesa_version%.*}"; do
	if [[ -d $candidate ]]; then
		series=$candidate
		break
	fi
done
if [[ -z $series ]]; then
	printf 'no vendored BC-250 patch series for Mesa %s\n' "$mesa_version" >&2
	printf 'The private driver must match the base image, so this is fatal.\n' >&2
	printf 'vendored series:\n' >&2
	for candidate in "$sources"/patches/*/; do
		printf '  %s\n' "${candidate%/}" >&2
	done
	exit 1
fi
series_name=${series##*/}
printf 'BC-250 patch series: %s\n' "$series_name"

dnf -y install meson ninja-build gcc gcc-c++ python3-mako python3-packaging \
  libdrm-devel wayland-devel wayland-protocols-devel libX11-devel \
  libxcb-devel xcb-util-keysyms-devel libXrandr-devel libxshmfence-devel \
  zlib-devel expat-devel bison flex glslang spirv-tools cbindgen \
  rust-packaging clang-devel llvm-devel python3-pyyaml git curl xz \
  glslc vulkan-headers vulkan-loader-devel

# The release tarball is verified against the SHA-256 published in the
# upstream release notes. A missing checksum is a hard failure: shipping an
# unverified driver is not acceptable.
tarball="mesa-${mesa_version}.tar.xz"
curl -fL --retry 3 "https://archive.mesa3d.org/${tarball}" -o "/tmp/${tarball}"
expected=$(curl -fsL --retry 3 "https://docs.mesa3d.org/relnotes/${mesa_version}.html" \
	| grep -m1 -oE "SHA256: [0-9a-f]{64}  ${tarball}" | grep -oE '[0-9a-f]{64}' || true)
if [[ -z $expected ]]; then
	printf 'no published SHA256 for %s in the upstream release notes\n' "$tarball" >&2
	exit 1
fi
printf '%s  /tmp/%s\n' "$expected" "$tarball" | sha256sum --check --status - \
	|| { printf 'SHA256 mismatch for %s\n' "$tarball" >&2; exit 1; }
printf 'Mesa %s tarball SHA256 verified\n' "$mesa_version"

tar -xf "/tmp/${tarball}" -C /tmp
cd "/tmp/mesa-${mesa_version}"

# Vendored BC-250 series for this Mesa release (compute queue, DirectMesh,
# FSR4), then this image's own diagnostic patch.
apply_series() {
	local dir=$1 patch
	for patch in "$dir"/*.patch; do
		[[ -f $patch ]] || continue
		git apply --check --whitespace=nowarn "$patch"
		git apply --whitespace=nowarn "$patch"
		printf 'applied %s\n' "$(basename "$patch")"
	done
}
apply_series "$series"
apply_series "$sources/patches/local"

# The base image's Mesa carries the OpenGamingCollective patches. Apply the
# same ones so the private driver exposes the same features (pageable device
# local memory, the SteamOS RADV defaults) as the system driver.
#
# limiter.patch is deliberately not applied: it only touches the Gallium DRI3
# loader, and this driver is built as a Vulkan-only RADV with no Gallium.
for patch in radv-defaults vram-overcommit; do
	url="${ogc_base}/${mesa_version}/${patch}.patch"
	if ! curl -fsSL --retry 3 -o "/tmp/ogc-${patch}.patch" "$url"; then
		printf 'OGC patch %s.patch is not published for Mesa %s\n' "$patch" "$mesa_version" >&2
		printf 'The private driver must match the base image, so this is fatal.\n' >&2
		exit 1
	fi
	# OGC re-tags the same patch content across Mesa releases while Mesa
	# keeps editing the file the patch touches, so a strict application can
	# fail on context drift that the change itself does not conflict with.
	# Try strict first, then again with one line of context dropped on each
	# side of the hunk. Both ways the added and removed lines still have to
	# match exactly, and the result is verified by checking that the patch
	# can be reversed against the patched tree.
	applied=
	for reduce in strict reduced; do
		case $reduce in
		strict) context=() ;;
		reduced) context=(-C1) ;;
		esac
		if git apply ${context[@]+"${context[@]}"} --check --whitespace=nowarn \
			"/tmp/ogc-${patch}.patch" 2>/tmp/ogc-apply.log; then
			git apply ${context[@]+"${context[@]}"} --whitespace=nowarn \
				"/tmp/ogc-${patch}.patch" 2>>/tmp/ogc-apply.log
			applied=$reduce
			break
		fi
	done
	if [[ -z $applied ]]; then
		printf 'OGC patch %s.patch does not apply to Mesa %s\n' "$patch" "$mesa_version" >&2
		cat /tmp/ogc-apply.log >&2
		printf 'The private driver must match the base image, so this is fatal.\n' >&2
		exit 1
	fi
	if ! git apply ${context[@]+"${context[@]}"} --reverse --check --whitespace=nowarn \
		"/tmp/ogc-${patch}.patch" 2>/dev/null; then
		printf 'OGC patch %s.patch did not land in the tree\n' "$patch" >&2
		exit 1
	fi
	printf 'applied OGC %s.patch (%s)\n' "$patch" "$applied"
done

# Strip the installed driver before copying /out into the final image layer.
meson setup /tmp/radv-build --prefix="$prefix" --libdir=lib64 --buildtype=release -Dstrip=true \
  -Dvulkan-drivers=amd -Dgallium-drivers= -Dplatforms=wayland,x11 \
  -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=false \
  -Dgles1=disabled -Dgles2=disabled -Dllvm=disabled \
  -Dvideo-codecs= -Dvulkan-layers= -Dtools= -Dshared-glapi=disabled \
  -Dbuild-tests=false
ninja -C /tmp/radv-build -j "${BC250_BUILD_JOBS:-4}"
DESTDIR=/out ninja -C /tmp/radv-build install

# Read current system game profiles at runtime, as the upstream installer does.
rm -rf "/out$prefix/share/drirc.d"
ln -s /usr/share/drirc.d "/out$prefix/share/drirc.d"
install -d "/out$prefix/etc" "$share" /out/usr/bin
ln -s /etc/drirc "/out$prefix/etc/drirc"
for helper in bc250-async-compute bc250-game-trace bc250-trace-report bc250-trace-sampler; do
  sed -e 's|/usr/local/lib/bc250-radv|/usr/lib/bc250-radv|g' \
      -e 's|/usr/local/share/bc250-async-compute|/usr/share/bc250-async-compute|g' \
      -e 's|/usr/local/bin/|/usr/bin/|g' \
      "$sources/$helper" > "/out/usr/bin/$helper"
  chmod 755 "/out/usr/bin/$helper"
done
cp -a "$sources/patches" "$sources/test" "$share/"
install -m 644 "$sources/LICENSE-MIT" "$sources/LICENSE-GPL-2.0" "$sources/NOTICE" \
  "$sources/UPSTREAM" "$share/"

{
	printf 'Mesa %s (base image version)\n' "$mesa_version"
	printf 'OGC patches: radv-defaults vram-overcommit\n'
	printf 'BC-250 patch series: %s (see PATCH-SERIES)\n' "$series_name"
} > "$share/VERSION"
install -m 644 "$sources/VERSION" "$share/PATCH-SERIES"
install -m 644 docs/license.rst "$share/MESA-LICENSE.rst"
BC250_NATIVE=1 bash "$share/test/build.sh"
