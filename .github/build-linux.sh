#!/bin/sh
# Builds a fully static ssg binary for Linux. Runs inside the
# crystallang/crystal:latest-alpine image with the checkout mounted as the
# working directory; see release.yml.
set -eux

LIBSASS_VERSION=3.6.6

apk add --no-cache pkgconf file

# Alpine's libsass-dev only ships libsass.so, which a --static build cannot
# link, so build the static archive from source.
wget -qO- "https://github.com/sass/libsass/archive/refs/tags/${LIBSASS_VERSION}.tar.gz" \
  | tar xz -C /tmp
make -C "/tmp/libsass-${LIBSASS_VERSION}" -j"$(nproc)" \
  BUILD=static LIBSASS_VERSION="$LIBSASS_VERSION" PREFIX=/usr \
  install install-headers

# sass.cr declares @[Link("sass")], which makes crystal ask `pkg-config sass`
# for the linker flags. libsass is C++, and with static archives -lstdc++
# must come after -lsass on the linker command line. --link-flags cannot do
# that (crystal puts those first), but a pkg-config module can.
mkdir -p /usr/lib/pkgconfig
cat > /usr/lib/pkgconfig/sass.pc <<PC
prefix=/usr
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: sass
Description: libsass, static archive
Version: ${LIBSASS_VERSION}
Libs: -L\${libdir} -lsass
Libs.private: -lstdc++
Cflags: -I\${includedir}
PC
pkg-config --static --libs sass

shards install --without-development
crystal build --release --no-debug --static src/main.cr -o ssg
file ssg
file ssg | grep -Eq 'static(ally|-pie) linked'
./ssg version
