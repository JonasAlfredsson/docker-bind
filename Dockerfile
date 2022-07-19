ARG app_version=0.1.1

FROM debian:bullseye-slim AS source
ARG DEBIAN_FRONTEND noninteractive

# In Debian the service runs as the user "bind" with uid 101 and gid 101.
ENV BIND_USER=bind \
    BIND_VERSION=1:9.16.27-1~deb11u1 \
    APP_VERSION=${app_version}

RUN apt-get update && apt-get install -y \
        wget \
        bind9="${BIND_VERSION}" \
    && \
# Obtain the latest keys for trust anchors (https://www.isc.org/bind-keys/).
    wget -q -O /etc/bind/bind.keys 'https://ftp.isc.org/isc/bind9/keys/9.11/bind.keys.v9_11' && \
# Download the latest hints file for the root servers.
    wget -q -O /etc/bind/db.root 'https://www.internic.net/zones/named.root' && \
# Make sure we point to the correct root hints file in our configs.
    sed -ri '/^(\s*)file "\/usr\/share\/dns\/root.hints";$/,${s//\1file "\/etc\/bind\/db.root";/;b};$q1' /etc/bind/named.conf.default-zones && \
# Create folder which will house any user defined configuration files.
    install -m 0775 -o "root" -g "${BIND_USER}" -d "/etc/bind/local-config" && \
# Remove configuration files we will override with our own.
    rm -fv \
        /etc/bind/named.conf.local \
        /etc/bind/named.conf.options \
        /etc/bind/rndc.key \
    && \
# Make so that the main configuration file only points towards the user created
# ones.
    echo 'include "/etc/bind/local-config/named.conf.logging";' > /etc/bind/named.conf && \
    echo 'include "/etc/bind/local-config/named.conf.options";' >> /etc/bind/named.conf && \
    echo 'include "/etc/bind/local-config/named.conf.local";' >> /etc/bind/named.conf && \
# Remove everything that is no longer necessary.
    apt-get remove --purge -y \
            wget \
    && \
    apt-get autoremove -y && apt-get clean && \
    rm -rf /var/lib/apt/lists/* &&\
# Create folder where some transient files will be stored by Bind.
    install -m 0775 -o "root" -g "${BIND_USER}" -d "/run/named" && \
# Create the logging folder which may be used when writing log files.
    install -m 0775 -o "${BIND_USER}" -g "${BIND_USER}" -d "/var/log/bind" && \
# Finally a folder for custom entrypoint scripts.
    mkdir /entrypoint.d



# Create the final Alpine image.
FROM alpine:3.16 AS alpine-target

# In Alpine the service runs as the user "named" with uid 100 and gid 101.
ENV BIND_USER=named \
    BIND_VERSION=9.16.29-r0 \
    APP_VERSION=${app_version}

RUN apk --update upgrade && \
    apk add --no-cache \
        bind="${BIND_VERSION}" \
    && \
# We will replace these files in a moment.
    rm -vf /etc/bind/* && \
# Create the cache folder which is expected by our config files.
    install -m 0770 -o "${BIND_USER}" -g "${BIND_USER}" -d "/var/cache/bind" && \
# Create the logging folder which may be used when writing log files.
    install -m 0775 -o "${BIND_USER}" -g "${BIND_USER}" -d "/var/log/bind" && \
# Finally a folder for custom entrypoint scripts.
    mkdir /entrypoint.d

# Get all the useful default files from the Debian installation since these are
# not included in the standard Alpine install.
# We explicitly list all files of interest so we get an error in case something
# is missing from the source.
COPY --from=source --chown=root:named \
    /etc/bind/bind.keys \
    /etc/bind/db.0 \
    /etc/bind/db.127 \
    /etc/bind/db.255 \
    /etc/bind/db.empty \
    /etc/bind/db.local \
    /etc/bind/db.root \
    /etc/bind/named.conf \
    /etc/bind/named.conf.default-zones \
    /etc/bind/zones.rfc1918 \
    /etc/bind/

COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 53 53/udp



# Create the final Debian image.
FROM source AS debian-target

COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 53 53/udp
