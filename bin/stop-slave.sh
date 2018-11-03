#!/bin/bash

rootdir="/opt/buildbot"
destdir="${rootdir}/virtualenv"
buildslavedir="${rootdir}/slave"
pidfile="${buildslavedir}/twistd.pid"

if [[ ! -d "${destdir}" ]]; then
    echo "Please install virtualenv"
    exit 1
fi

source "${destdir}/bin/activate"

if [[ -e "${pidfile}" ]]; then
    buildslave stop "${buildslavedir}"
    rm -f "${pidfile}"
fi
