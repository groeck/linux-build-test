#!/bin/bash

for x in $*
do
    md5sum $x > $x.md5
done
