#!/bin/bash

cleanup()
{
    for dest in $*; do
	echo "${dest}: Cleaning up /tmp"
	if ! ssh -t ${dest} /opt/buildbot/bin/cleanup-tmp.sh >/dev/null 2>&1; then
	   echo "    Failed to clean up ${dest}"
	fi
    done
}

# Clean up /tmp/ when starting buildbot to avoid unnecessary build
# failures due to disk space problems.
if [[ "$1" = "start" ]]; then
    cleanup desktop mars jupiter saturn server
fi

rootdir="/opt/buildbot"
vdir="${rootdir}/virtualenv"
pidfile="${buildbotdir}/twistd.pid"

if [[ ! -d "${vdir}" ]]; then
    if [[ ! -x /usr/bin/virtualenv ]]; then
	echo "Please install virtualenv"
	exit 1
    fi
    virtualenv "${vdir}"
    source "${vdir}/bin/activate"
    pip install buildbot==0.8.14
    # Needs patch - see README
else
    source "${vdir}/bin/activate"
fi

buildbot $*
