#!/bin/bash

rootdir="/opt/buildbot"
vdir="${rootdir}/virtualenv"
pidfile="${rootdir}/slave/twistd.pid"

if [[ -e "${pidfile}" ]]; then
    pid="$(cat ${pidfile})"
    cmd=$(ps -o ucmd= ${pid} | awk '{ print $1 }')
    if [[ "${cmd}" != "buildslave" ]]; then
	# The pid file exists, and a process may be associated with it,
	# but it does not point to a buildslave.
	# This may prevent the slave from starting. Remove the file.
	rm -f "${pidfile}"
    fi
fi

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
