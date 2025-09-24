#!/bin/sh -eu
# This file was created so we can reuse the same meson setup command across
# both the Debian and the Alpine containers.
#
# Input arguments:
# $1: The "build" directory to output to.
#
meson setup "${1}" \
    --buildtype release \
    --install-umask 0027 \
    --strip \
    --prefix=/usr \
    --sysconfdir=/etc/bind \
    --localstatedir=/var \
    -D doc=disabled \
    -D cap=enabled \
    -D dnstap=enabled \
    -D doh=enabled \
    -D fips=enabled \
    -D geoip=enabled \
    -D gssapi=enabled \
    -D idn=enabled \
    -D line=enabled \
    -D lmdb=enabled \
    -D stats-json=enabled \
    -D stats-xml=disabled \
    -D zlib=enabled \
    -D cachedb=qpcache \
    -D zonedb=qpzone \
    -D locktype=adaptive \
    -D jemalloc=enabled \
    -D rcu-flavor=membarrier \
    -D tracing=disabled \
    -D auto-validation=enabled \
    -D developer=disabled \
    -D leak-detection=disabled
