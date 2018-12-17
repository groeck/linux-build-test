#!/bin/bash
# This script generates SD card disk images suitable for use with QEMU.
#
# Copyright (c) 2015 Guenter Roeck
#
# Derived from:
# mkimage.sh
#   Copyright (C) 2011 Ash Charles
# Based on:
#   Narcissus - Online image builder for the angstrom distribution
#   Copyright (C) 2008 - 2011 Koen Kooi
#   Copyright (C) 2010	Denys Dmytriyenko
# and
#   Linaro Images Tools.
#   Author: Guilherme Salgado <guilherme.salgado@linaro.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

LC_ALL=C
set -e
PATH=${PATH}:/sbin

imgsize=268435456 # 256M

usage()
{
    echo "Usage:"
    echo "  $0 -k kernel -m MLO -u uboot -r rootfs [-d dtb] [-b boot script ] [ -s size ] image"
    exit 1
}

make_image()
{
    local tmpfile=/tmp/sdimage.$$.img

    qemu-img create -f raw ${tmpfile} ${imgsize}

    {
    echo 63,144522,0x0C,*
    echo 144585,369495,,-
    } | sfdisk -u S ${tmpfile} &> /dev/null

    # Reverse engineer partition setup
    BYTES_PER_SECTOR="$(fdisk -l -u ${tmpfile} | grep Units | awk '{print $8}')"
    VFAT_SECTOR_OFFSET="$(fdisk -l -u ${tmpfile} | grep ${tmpfile}1 | awk '{print $3}')"
    VFAT_SECTORS="$(fdisk -l -u ${tmpfile} | grep ${tmpfile}1 | awk '{print $5}')"
    EXT3_SECTOR_OFFSET="$(fdisk -l -u ${tmpfile} | grep ${tmpfile}2 | awk '{print $2}')"
    EXT3_SECTORS="$(fdisk -l -u ${tmpfile} | grep ${tmpfile}2 | awk '{print $4}')"

    mv ${tmpfile} ${outfile}
}

populate_image() 
{
    local tmpdir=/tmp/rootfs.$$
    local fatfs=/tmp/fat.img.$$
    local ext2fs=/tmp/ext2.img.$$
    local fatblocks=$((${VFAT_SECTORS} / 2))
    local ext2blocks=$((${EXT3_SECTORS} / 2))

    echo "[ Generate and copy fat partition ]"

    rm -rf ${tmpdir} ${fatfs} ${ext2fs}
    mkdir -p ${tmpdir}

    if [ -n ${bootscript} ]
    then
	mkimage -C none -A arm -T script -d ${bootscript} boot.scr
	cp boot.scr /${tmpdir}/boot.scr
    fi
    if [ -n "${dtbfile}" ]
    then
	cp ${dtbfile} /${tmpdir}/devicetree.dtb
    fi
    cp ${mlo} /${tmpdir}/MLO
    cp ${uboot} /${tmpdir}/u-boot.bin
    cp ${kernel} /${tmpdir}/uImage

    /opt/buildbot/bin/genfatfs -d ${tmpdir} -b ${fatblocks} ${fatfs}

    dd if=${fatfs} bs=512 seek=${VFAT_SECTOR_OFFSET} count=${VFAT_SECTORS} of=${outfile} conv=notrunc

    echo "[ Copying file system ]"

    if [[ "${rootfs}" = *ext2 ]]; then
	cp "${rootfs}" "${ext2fs}"
	chmod +w "${ext2fs}"
    else
	rm -rf ${tmpdir}
	mkdir -p ${tmpdir}

	echo "[ Extracting to ${tmpdir} ]"
	if [[ "${rootfs}" = *cpio ]]; then
	    local prefix=""
	    if [[ "${rootfs}" != /* ]]; then
		prefix="$(pwd)"
	    fi
	    (cd ${tmpdir} ; cpio -i < "${prefix}/${rootfs}")
	else
	    tar xaf ${rootfs} -C ${tmpdir}
	fi

	echo "[ Generating ${ext2fs} with ${ext2blocks} blocks ]"
	genext2fs -U -N 4096 -b ${ext2blocks} -d ${tmpdir} ${ext2fs}
	# fsck.ext3 ${ext2fs}
	# e2label ${ext2fs} rootfs
	echo "[ Done ${ext2fs} ]"
    fi
    tune2fs -j ${ext2fs}

    dd if=${ext2fs} bs=512 seek=${EXT3_SECTOR_OFFSET} count=${EXT3_SECTORS} of=${outfile} conv=notrunc

    echo "[ Clean up ]"

    rm -rf ${tmpdir} ${fatfs} ${ext2fs}
}

while getopts b:d:k:m:r:s:u: opt
do
    case ${opt} in
    b) bootscript=$OPTARG;;
    d) dtbfile=$OPTARG;;
    k) kernel=$OPTARG;;
    m) mlo=$OPTARG;;
    r) rootfs=$OPTARG;;
    s) imgsize=$((${OPTARG} * 1048576));;
    u) uboot=$OPTARG;;
    *) usage;;
    esac
done

shift $(($OPTIND - 1))

outfile=$1

if [ -z "${outfile}" ]
then
	echo "Output file not specified" 
	usage
fi

if [ -z "${kernel}" -o ! -e "${kernel}" ]
then
	echo "kernel not specified or not found" 
	usage
fi

if [ -z "${uboot}" -o ! -e "${uboot}" ]
then
	echo "u-boot image \"${uboot}\" not specified or not found" 
	usage
fi

if [ -z "${rootfs}" -o ! -e "${rootfs}" ]
then
	echo "root file system \"${rootfs}\" not specified or not found" 
	usage
fi

if [ -z "${mlo}" -o ! -e "${mlo}" ]
then
	echo "MLO not specified or not found" 
	usage
fi

if [ -n "${dtbfile}" -a ! -e "${dtbfile}" ]
then
	echo "dtb file ${dtbfile} not found" 
	usage
fi

if [ -n "${bootscript}" -a ! -e "${bootscript}" ]
then
	echo "boot script ${bootscript} not found" 
	usage
fi

make_image
populate_image
