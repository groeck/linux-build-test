#!/bin/bash

if [ -z "$1" ]; then
    echo "Need valid parameters"
    exit 1
fi

doit()
{
	echo scp "$2" "$1":
	scp "$2" "$1":
	if [ $? -ne 0 ]; then
		echo "scp failed"
		exit 1
	fi
	ssh -t $1 /opt/buildbot/bin/install-gcc.sh $(basename $2)
}

sudo tar xf $1 -C /opt/kernel

doit desktop $1
doit mars $1
doit jupiter $1
doit saturn $1
