#!/bin/bash

basedir="$(cd $(dirname $0); pwd)"
slavedir="${basedir}/../slave"

cd "${slavedir}" || exit 1

for x in */build; do
    echo "Cleaning $x:"
    if [ -d "$x" ]; then
	if [ -e "$x/.git/gc.log" ]; then
	    git -C "$x" prune
	    rm -f "$x/.git/gc.log"
	fi
	git -C "$x" gc
    fi
done
