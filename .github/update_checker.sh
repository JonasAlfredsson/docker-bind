#!/bin/bash
set -euo pipefail

################################################################################
#
# This script will query the repository where the Bind source files are located
# and try to parse and find the latest version.
# If any changes are found the Makefile will be updated.
#
################################################################################

# Prepare some paths we are going to use.
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename ${BASH_SOURCE[0]})"
MAKEFILE_PATH="${SCRIPT_DIR}/../Makefile"

# Use the version_extractor.sh script to obtain the current version.
while read v; do
    export "${v}"
done < <("${SCRIPT_DIR}/version_extractor.sh" "${MAKEFILE_PATH}")
echo "Current version is ${APP_MAJOR}.${APP_MINOR}.${APP_PATCH}" >&2


# Query the download page and iterate over each line of the content returned.
newVersion="false"
while read p; do
    # Try to find something that looks like a version number.
    # We do not include any "rc1" or similar releases, only a "1.23.45" number
    # without any suffixes.
    version=$(echo "${p}" | sed -n -r -e 's/^.*?href="([1-9][0-9]*\.[0-9]+\.[0-9]+)\/".*$/\1/p')
    if [ -z "${version}" ]; then
        # No version found on this line, just continue with the next one.
        continue
    fi

    # Create separate variables to make it easier to work with.
    major=$(echo ${version} | cut -d. -f 1)
    minor=$(echo ${version} | cut -d. -f 2)
    patch=$(echo ${version} | cut -d. -f 3)
    echo "Comparing with ${major}.${minor}.${patch}" >&2

    # Compare the release found on the page with what we have right now.
    if [ "${major}" -gt "${APP_MAJOR}" ]; then
        APP_MAJOR="${major}"
        APP_MINOR="${minor}"
        APP_PATCH="${patch}"
        newVersion="true"
    elif [ "${major}" -eq "${APP_MAJOR}" ]; then
        if [ "${minor}" -gt "${APP_MINOR}" ]; then
            APP_MINOR="${minor}"
            APP_PATCH="${patch}"
            newVersion="true"
        elif [ "${minor}" -eq "${APP_MINOR}" ]; then
            if [ "${patch}" -gt "${APP_PATCH}" ]; then
                APP_PATCH="${patch}"
                newVersion="true"
            fi
        fi
    fi
done < <(curl -sSLf https://downloads.isc.org/isc/bind9)



# If there is a new version available we update the relevant files with this
# information.
if [ "${newVersion}" == "true" ]; then
    sed -i -E "s/^BIND_VERSION=\".*?\"$/BIND_VERSION=\"${APP_MAJOR}\.${APP_MINOR}\.${APP_PATCH}\"/g" "${MAKEFILE_PATH}"
    echo COMMIT_MESSAGE="Bind version ${APP_MAJOR}.${APP_MINOR}.${APP_PATCH}"
else
    echo "No changes detected" >&2
fi
exit 0;
