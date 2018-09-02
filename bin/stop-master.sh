#!/bin/bash

rootdir="/opt/buildbot"
vdir="${rootdir}/virtualenv"
buildbotdir="${rootdir}/master"
pidfile="${buildbotdir}/twistd.pid"

if [[ ! -d "${vdir}" ]]; then
    echo "No virtual environment"
    exit 1
fi
source "${vdir}/bin/activate"

if [[ -e "${pidfile}" ]]; then
    buildbot stop "${buildbotdir}"
    rm -f "${pidfile}"
fi
