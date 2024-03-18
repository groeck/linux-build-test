#!/bin/bash

__cleanup()
{
    rv=$?
    rm -rf ${BUILDDIR} ${LOG}
    exit ${rv}
}

dumplog()
{
    local maxsize="$1"
    local log="$2"
    local logsize="$(cat ${log} | wc -l)"

    # strip off path name - it is irrelevant for the log
    local basedir="$(pwd | sed -e 's/\//\\\//g')\/"
    sed -i -e "s/${basedir}//" "${log}"

    # Empty lines are irrelevant / don't add value.
    sed -i -e '/^[ 	]*$/d' "${log}"

    echo "--------------"
    echo "Error log:"
    if [[ ${logsize} -lt ${maxsize} ]]; then
	cat "${log}"
    else
	local splitsize=$((maxsize / 3))
	head "-${splitsize}" "${log}"
	echo "..."
	echo "[skipped]"
	echo "..."
	tail "-${splitsize}" "${log}"
    fi
    echo "--------------"
}

# Return kernel version based on parameters
kernel_version()
{
    local v1=${1:-0}
    local v2=${2:-0}

    echo "$((v1 * 65536 + v2))"
}

# Current Linux kernel version
linux_version_code="$(kernel_version $(git describe --match 'v*' | cut -f1 -d- | sed -e 's/\./ /g' | sed -e 's/v//'))"
