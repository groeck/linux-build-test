#!/bin/bash

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
    pip install buildbot-slave==0.8.14
    # Needs patch - see README
else
    source "${vdir}/bin/activate"
fi

buildslave $*
