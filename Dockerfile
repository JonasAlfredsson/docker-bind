# Have a common base for the entire Debian build branch.
FROM debian:13.1-slim AS base
ARG DEBIAN_FRONTEND=noninteractive
LABEL maintainer="Jonas Alfredsson <jonas.alfredsson@protonmail.com>"

# Have a common base for the entire Alpine build branch.
FROM alpine:3.22 AS base-alpine
LABEL maintainer="Jonas Alfredsson <jonas.alfredsson@protonmail.com>"
RUN apk add --no-cache \
        ca-certificates


################################################################################
#
# Beginning of the "downloader" preparation build target.
#
################################################################################

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

# As a last step for this build target we copy the "meson setup" script which
# we use to keep the configuration in sync between both the Debian and Alpine
# build tracks.
COPY ./meson-setup.sh ./


################################################################################
#
# Beginning of the Debian build flow.
#
################################################################################

# Continue in a new stage to build what we have downloaded (Debian).
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
    ./meson-setup.sh "/build"

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

# We need to do some platfrom specific workarounds in the build script, so bring
# this information in to the build environment.
ARG TARGETPLATFORM

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
        $(if [ "$TARGETPLATFORM" = "linux/arm/v7" ]; then echo "liburcu8t64"; else echo "liburcu8"; fi) \
        $(if [ "$TARGETPLATFORM" = "linux/arm/v7" ]; then echo "libuv1t64"; else echo "libuv1"; fi) \
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


################################################################################
#
# Beginning of the Alpine build flow.
#
################################################################################

# Continue in a new stage to build what we have downloaded (Alpine).
FROM base-alpine AS builder-alpine
RUN set -e && apk add --no-cache \
# These initial packages are more related to extracting and compiling the code.
        g++ \
        make \
        perl \
        curl \
        pkgconfig \
        protobuf-c-compiler \
        netcat-openbsd \
# Below here are all the libraries needed by Bind for all features.
        openssl-dev \
        userspace-rcu-dev \
        libuv-dev \
        libcap-dev \
        nghttp2-dev \
        libxml2-dev \
        zlib-dev \
        lmdb-dev \
        libmaxminddb-dev \
        protobuf-c-dev \
        libidn2-dev \
        libedit-dev \
        krb5-dev \
        fstrm-dev \
        json-c-dev \
        cmocka-dev \
        jemalloc-dev

# Needed in order to install Python packages via PIP after PEP 668 was
# introduced, but I believe this is safe since we are in a container without
# any real need to cater to other programs/environments.
ARG PIP_BREAK_SYSTEM_PACKAGES=1

# Install Python and then meson from pip to get the same version as Debian.
RUN apk add --no-cache \
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
    ./meson-setup.sh "/build"

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
FROM base-alpine AS final-alpine

# The Alpine packages create the "named" (100/101) user on the system, and in
# order to be compatible with this we do the same.
# NOTE: Debian uses "bind" (101/101) instead.
ENV BIND_USER=named

RUN set -e && \
# Create the group and user for our Bind process.
    addgroup -S -g 101 ${BIND_USER} && \
    adduser -S -D -H -s /sbin/nologin -g "Bind user" \
        -G ${BIND_USER} -u 100 ${BIND_USER} \
    && \
# Install all the runtime dependencies.
    set -e && apk add --no-cache \
        libssl3 \
        userspace-rcu \
        libuv \
        libcap \
        nghttp2 \
        zlib \
        lmdb \
        libmaxminddb \
        protobuf-c \
        libidn2 \
        libedit \
        krb5 \
        fstrm \
        json-c \
        jemalloc \
    && \
# After this we create a couple of folders that should exist and be writable
# for the Bind process.
    install -m 0770 -o "${BIND_USER}" -g "${BIND_USER}" -d "/var/cache/bind" && \
    install -m 0775 -o "${BIND_USER}" -g "${BIND_USER}" -d "/var/log/bind" && \
    install -m 0775 -o "root" -g "${BIND_USER}" -d "/run/named" && \
    install -m 0775 -o "root" -g "${BIND_USER}" -d "/etc/bind/local-config" && \
    mkdir /entrypoint.d

# Now we have all the paths for all the files that were installed through
# meson, so we only want to copy these over to our otherwise clean image.
RUN --mount=type=bind,from=builder-alpine,source=/,target=/source \
    /source/copier.sh "/source"

# Finally we copy all of our default configuration files, as well as our
# entrypoint, into the final container and update the settings to reflect this.
COPY ./root/ /
ENTRYPOINT [ "/entrypoint.sh" ]
CMD []

# Bind uses both TCP and UDP on port 53.
EXPOSE 53 53/udp
