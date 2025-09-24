#!/bin/sh -eu

# This variables takes the first input argument and is used to specify in which
# directory the source files are located.
SOURCE_DIR="${1}"

while IFS='' read -r LINE || [ -n "${LINE}" ]; do
    if echo "${LINE}" | egrep -q '^\s*#'; then
        # This means it is a comment line in the file; skip.
        continue
    fi
    if [ -f "${SOURCE_DIR}${LINE}" ]; then
        cp -v "${SOURCE_DIR}${LINE}" "${LINE}"
    elif [ -d "${SOURCE_DIR}${LINE}" ]; then
        mkdir -pv "${LINE}"
    else
        echo "Don't know how to handle '${LINE}'"
        exit 1
    fi
done < "${SOURCE_DIR}/build/meson-logs/install-log.txt"
