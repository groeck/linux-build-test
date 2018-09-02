#!/bin/bash

rootdir="/opt/buildbot"
destdir="${rootdir}/virtualenv"
buildslavedir="${rootdir}/slave"

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

buildslave start "${buildslavedir}"
