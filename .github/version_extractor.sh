#!/bin/bash
set -eo pipefail

################################################################################
#
# This script will try to extract the Bind version from the file targeted.
#
# $1: The file to scan
#
################################################################################


version=$(sed -n -r -e 's&^BIND_VERSION="([1-9]+\.[0-9]+\.[0-9]+)"$&\1&p' "${1}")

if [ -z "${version}" ]; then
    echo "Could not extract version from '${1}'"
    exit 1
fi

echo "APP_MAJOR=$(echo ${version} | cut -d. -f 1)"
echo "APP_MINOR=$(echo ${version} | cut -d. -f 2)"
echo "APP_PATCH=$(echo ${version} | cut -d. -f 3)"
