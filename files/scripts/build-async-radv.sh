#!/usr/bin/env bash
# Build a private RADV and its correctness tests in a disposable Fedora stage.
set -euo pipefail
mesa_version=26.2.5
mesa_sha256=794b3d1729075dae7ebd47c7283b7ca0cdb5dec668f7f11cc0a5d82f6138a0a5
prefix=/usr/lib/bc250-radv
sources=/tmp/bc250-async
share=/out/usr/share/bc250-async-compute

dnf -y install meson ninja-build gcc gcc-c++ python3-mako python3-packaging \
  libdrm-devel wayland-devel wayland-protocols-devel libX11-devel \
  libxcb-devel xcb-util-keysyms-devel libXrandr-devel libxshmfence-devel \
  zlib-devel expat-devel bison flex glslang spirv-tools cbindgen \
  rust-packaging clang-devel llvm-devel python3-pyyaml git curl xz \
  glslc vulkan-headers vulkan-loader-devel
curl -fL --retry 3 "https://archive.mesa3d.org/mesa-${mesa_version}.tar.xz" -o /tmp/mesa.tar.xz
printf '%s  /tmp/mesa.tar.xz\n' "$mesa_sha256" | sha256sum -c -
tar -xf /tmp/mesa.tar.xz -C /tmp
cd "/tmp/mesa-${mesa_version}"
for patch in "$sources"/patches/*.patch; do
  git apply --check "$patch"
  git apply "$patch"
done
# Strip the installed driver before copying /out into the final image layer.
meson setup /tmp/radv-build --prefix="$prefix" --libdir=lib64 --buildtype=release -Dstrip=true \
  -Dvulkan-drivers=amd -Dgallium-drivers= -Dplatforms=wayland,x11 \
  -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=false \
  -Dgles1=disabled -Dgles2=disabled -Dllvm=disabled \
  -Dvideo-codecs= -Dvulkan-layers= -Dtools= -Dshared-glapi=disabled
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
install -m 644 "$sources/LICENSE" "$sources/UPSTREAM" "$share/"
printf 'Mesa %s; async patch revision 56bf06b986f4639c32a669e9cdd31cdf7fba44b6\n' "$mesa_version" > "$share/VERSION"
install -m 644 docs/license.rst "$share/MESA-LICENSE.rst"
BC250_NATIVE=1 bash "$share/test/build.sh"
