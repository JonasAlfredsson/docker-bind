#!/bin/sh
set -e

# Helper function used to make all logging messages look similar.
log() {
    echo "$(date '+%d-%b-%Y %H:%M:%S.000') entrypoint: $1: $2"
}
log "info" "Starting Bind container"

# Execute any potential shell scripts in the entrypoint.d/ folder.
find "/entrypoint.d/" -follow -type f -print | sort -V | while read -r f; do
    case "${f}" in
        *.sh)
            if [ -x "${f}" ]; then
                log "info" "Launching ${f}";
                "${f}"
            else
                log "info" "Ignoring ${f}, not executable";
            fi
            ;;
        *)
            log "info" "Ignoring ${f}";;
    esac
done

# Verify that the configuration has no errors already here.
# The reason for this is that we want to use the "-f" flag when launching Bind
# so that it loads the logging configuration from a file, but then (annoyingly)
# nothing will be printed in case of configuration errors.
# Alternatively you can set BIND_LOG="-g" to force all output to stderr.
named-checkconf /etc/bind/named.conf

exec /usr/sbin/named -c /etc/bind/named.conf ${BIND_LOG="-f"} -u "${BIND_USER}" $@
