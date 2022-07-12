#!/bin/bash
set -eo pipefail

################################################################################
#
# This is a helper script which will try to extract the version of the Bind
# service installed in the targeted image.
#
# $1: The taget image [Alpine|Debian]
# $2: Target filepath
#
################################################################################

if [ "${1}" == "Alpine" ]; then
    version=$(sed -n -r -e 's/\s*BIND_VERSION=([1-9]+\.[0-9]+\.[0-9]+)-.*$/\1/p' "${2}")
elif [ "${1}" == "Debian" ]; then
    version=$(sed -n -r -e 's/\s*BIND_VERSION=1:([1-9]+\.[0-9]+\.[0-9]+)-.*$/\1/p' "${2}")
else
    echo "Unknown option '${1}'"
    exit 1
fi

if [ -z "${version}" ]; then
    echo "Could not extract Bind version from '${1}'"
    exit 1
fi

echo "::set-output name=SEM_VER_MAJOR::$(echo ${version} | cut -d. -f 1)"
echo "::set-output name=SEM_VER_MINOR::$(echo ${version} | cut -d. -f 1-2)"
echo "::set-output name=SEM_VER_PATCH::$(echo ${version} | cut -d. -f 1-3)"
