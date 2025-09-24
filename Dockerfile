# Have a common base for the entire Debian build branch.
FROM debian:trixie-slim AS base
ARG DEBIAN_FRONTEND=noninteractive
LABEL maintainer="Jonas Alfredsson <jonas.alfredsson@protonmail.com>"


# We start with a minimal base image we can reuse for the different build stages.
FROM base AS build-base
RUN apt-get update && \
    apt-get install -y \
        apt-transport-https \
    && \
    apt-get install -y \
        curl \
        gnupg2 \
        xz-utils


# The downloader stage will be used to fetch and unpack all the source code.
FROM build-base AS downloader
# Import the public keys that can be used for verifying the downloaded package.
# Keyblock can be found here: https://www.isc.org/pgpkey/
RUN --mount=type=bind,source=./isc-keyblock.asc,target=/isc-keyblock.asc \
    install -m 0700 -o root -g root -d /root/.gnupg && \
    gpg2 --import /isc-keyblock.asc && \
    gpg2 --update-trustdb

# Continue working in this directory.
WORKDIR /downloads

# Download and unpack the correct tarball (also verify the signature).
ARG BIND_VERSION
RUN curl -LORf "https://downloads.isc.org/isc/bind9/${BIND_VERSION}/bind-${BIND_VERSION}.tar.xz{,.asc}" && \
    gpg2 --no-options --verbose --keyid-format 0xlong --keyserver-options auto-key-retrieve=true \
        --verify "./bind-${BIND_VERSION}.tar.xz.asc" "./bind-${BIND_VERSION}.tar.xz"

# Change to a new workdir to make sure we are in a clean workspace.
WORKDIR /source

# Extract the archive we downloaded to this clean workspace.
RUN tar -xvf /downloads/bind-${BIND_VERSION}.tar.xz --strip-components=1


# Continue in a new stage to build what we have downloaded.
FROM build-base AS builder
RUN apt-get install -y \
# These initial packages are more related to extracting and compiling the code.
        build-essential \
        perl \
        pkg-config \
        protobuf-c-compiler \
        netcat-openbsd \
# Below here are all the libraries needed by Bind for all features.
        libssl-dev=3* \
        liburcu-dev \
        libuv1-dev \
        libcap-dev \
        libnghttp2-dev \
        libxml2-dev \
        zlib1g-dev \
        liblmdb-dev \
        libmaxminddb-dev \
        libprotobuf-c-dev \
        libidn2-dev \
        libedit-dev \
        libkrb5-dev \
        libfstrm-dev \
        libjson-c-dev \
        libcmocka-dev \
        libjemalloc-dev

# Needed in order to install Python packages via PIP after PEP 668 was
# introduced, but I believe this is safe since we are in a container without
# any real need to cater to other programs/environments.
ARG PIP_BREAK_SYSTEM_PACKAGES=1

# Install Python and then meson from pip to get up to date release.
RUN apt-get install -qq -y \
        python3 \
    && \
# Install the latest version of PIP, Setuptools and Wheel.
    curl -L 'https://bootstrap.pypa.io/get-pip.py' | python3 && \
# Install the necessary pip packages.
    pip install meson ninja

# Use the coming "source" folder as our workdir.
WORKDIR /source

# Mount the "source" folder from the download stage and prepare for building.
RUN --mount=type=bind,from=downloader,source=/source,target=/source \
# Create an output directory we can write to.
    mkdir /build && \
    meson setup /build \
# Try to mimic the install paths used in the Debian packages.
        --buildtype release \
        --install-umask 0027 \
        --strip \
        --prefix=/usr \
        --sysconfdir=/etc/bind \
        --localstatedir=/var \
# Enable basically all of Bind's features (that are not test or docs related).
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

# We are now ready to compile the program.
RUN --mount=type=bind,from=downloader,source=/source,target=/source \
    meson compile -C /build

# And finally we install it. HOWEVER, this is done just so all files are sent
# to their correct places, which is then logged by meson.
RUN --mount=type=bind,from=downloader,source=/source,target=/source \
    meson install -C /build && \
# Sort the log file for simpler handling of directories later.
    sort /build/meson-logs/install-log.txt -o /build/meson-logs/install-log.txt

# Finally we inject the "copier" script into this image, which will be used to
# perform the "meson install" step again, but without needing all the
# dependencies.
COPY copier.sh /



# This will be the final stage which will just contain the Bind binaries and its
# dependencies.
FROM base AS final

# The Debian packages create the "bind" (101/101) user on the system, and in
# order to be compatible with this we do the same.
# NOTE: Alpine uses "named" (100/101) instead.
ENV BIND_USER=bind

RUN apt-get update && \
# First we install some stuff needed during this initial configuration.
    apt-get install -y \
        apt-transport-https \
        adduser \
    && \
# Create the group and user for our Bind process.
    addgroup --system --gid 101 ${BIND_USER} && \
    adduser --system --disabled-login --no-create-home --shell /bin/false --gecos "Bind user" \
        --ingroup ${BIND_USER} --uid 101 ${BIND_USER} \
    && \
# Install all the runtime dependencies.
    apt-get install -y \
        openssl \
        liburcu8 \
        libuv1 \
        libcap2 \
        libnghttp2-14 \
        zlib1g \
        liblmdb0 \
        libmaxminddb0 \
        libprotobuf-c1 \
        libidn2-0 \
        libedit2 \
        libkrb5-3 \
        libgssapi-krb5-2 \
        libfstrm0 \
        libjson-c5 \
        libjemalloc2 \
    && \
# After this we create a couple of folders that should exist and be writable
# for the Bind process.
    install -m 0770 -o "${BIND_USER}" -g "${BIND_USER}" -d "/var/cache/bind" && \
    install -m 0775 -o "${BIND_USER}" -g "${BIND_USER}" -d "/var/log/bind" && \
    install -m 0775 -o "root" -g "${BIND_USER}" -d "/run/named" && \
    install -m 0775 -o "root" -g "${BIND_USER}" -d "/etc/bind/local-config" && \
    mkdir /entrypoint.d \
    &&\
# Perform some cleanup afterwards to keep size minimal.
    apt-get purge -y \
        apt-transport-https \
        adduser \
    && \
    apt-get -y autoremove && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/*

# Now we have all the paths for all the files that were installed through
# meson, so we only want to copy these over to our otherwise clean image.
RUN --mount=type=bind,from=builder,source=/,target=/source \
    /source/copier.sh "/source"

# Finally we copy all of our default configuration files, as well as our
# entrypoint, into the final container and update the settings to reflect this.
COPY ./root/ /
ENTRYPOINT [ "/entrypoint.sh" ]
CMD []

# Bind uses both TCP and UDP on port 53.
EXPOSE 53 53/udp
