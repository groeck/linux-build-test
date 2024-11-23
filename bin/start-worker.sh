#!/bin/bash

rootdir="/opt/buildbot"
destdir="${rootdir}/virtualenv"
buildslavedir="${rootdir}/slave"
pidfile="${buildslavedir}/twistd.pid"

if [[ ! -d "${destdir}" ]]; then
    if [[ ! -x /usr/bin/virtualenv ]]; then
	echo "Please install virtualenv"
	exit 1
    fi
    virtualenv "${destdir}"
    source "${destdir}/bin/activate"
    pip install buildbot-slave==0.8.14
else
    source "${destdir}/bin/activate"
fi

if [[ -e "${pidfile}" ]]; then
    buildslave stop "${buildslavedir}"
    rm -f "${pidfile}"
fi

buildslave start "${buildslavedir}"
