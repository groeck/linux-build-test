#!/bin/bash

ARCH=$1
BRACNH=$2
BUILDDIR=$3

basedir=$(cd $(dirname $0); pwd)

cat ${basedir}/branches/${BRANCH}/config.local >> ${BUILDDIR}/.config
cp ${basedir}/branches/${BRANCH}/iwlwifi-7260-16.ucode /tmp
