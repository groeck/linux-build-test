#!/bin/bash

basedir="$(cd $(dirname $0); pwd)"
slavedir="${basedir}/../slave"

cd "${slavedir}"

for x in */build; do
    echo "Cleaning $x:"
    (cd $x; git gc)
done
