#!/bin/bash

basedir=$(cd $(dirname $0); pwd)
. ${basedir}/stable-build-targets.sh

LOG=/tmp/log.$$

PATH_ALPHA=/opt/kernel/gcc-4.6.3-nolibc/alpha-linux/bin
PATH_ARM=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/armv5te-poky-linux-gnueabi
PATH_ARC=/opt/kernel/arc/gcc-4.4.7/usr/bin
PATH_AVR32=/opt/kernel/gcc-4.2.4-nolibc/avr32-linux/bin
PATH_BFIN=/opt/kernel/gcc-4.6.3-nolibc/bfin-uclinux/bin
PATH_CRIS=/opt/kernel/gcc-4.6.3-nolibc/cris-linux/bin
PATH_FRV=/opt/kernel/gcc-4.6.3-nolibc/frv-linux/bin
PATH_IA64=/opt/kernel/gcc-4.6.3-nolibc/ia64-linux/bin
PATH_M68=/opt/kernel/gcc-4.6.3-nolibc/m68k-linux/bin
PATH_M68_NOMMU=/usr/local/bin
PATH_MICROBLAZE=/opt/kernel/gcc-4.8.0-nolibc/microblaze-linux/bin
PATH_MIPS=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/mips32-poky-linux
PATH_PARISC=/opt/kernel/gcc-4.6.3-nolibc/hppa-linux/bin
PATH_PARISC64=/opt/kernel/gcc-4.6.3-nolibc/hppa64-linux/bin
PATH_PPC=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin/ppc64e5500-poky-linux
PATH_S390=/opt/kernel/gcc-4.6.3-nolibc/s390x-linux/bin
PATH_SH4=/opt/kernel/gcc-4.6.3-nolibc/sh4-linux/bin
PATH_SPARC=/opt/kernel/gcc-4.6.3-nolibc/sparc64-linux/bin
PATH_TILE=/opt/kernel/gcc-4.6.2-nolibc/tilegx-linux/bin
PATH_X86=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/x86_64-poky-linux
PATH_XTENSA=/opt/kernel/gcc-4.6.3-nolibc/xtensa-linux/bin

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
branch=$(git branch | cut -f2 -d' ')

errors=0
builds=0

ref=$(git describe)
echo
echo "Build reference: ${ref}"
echo

ARCH=$1

# clean up source directory expected to be done by caller
# Do it again to be able to call script directly.
git clean -x -f -d -q

SUBARCH=""
declare -a fixup
case ${ARCH} in
    alpha)
	cmd=(${cmd_alpha[*]})
	PREFIX="alpha-linux-"
	PATH=${PATH_ALPHA}:${PATH}
	;;
    arc)
	cmd=(${cmd_arc[*]})
	fmax=$(expr ${#fixup_arc[*]} - 1)
	for f in $(seq 0 ${fmax})
	do
	    fixup[$f]=${fixup_arc[$f]}
	done
	PREFIX="arc-buildroot-linux-uclibc-"
	PATH=${PATH_ARC}:${PATH}
	;;
    arm)
	cmd=(${cmd_arm[*]})
	PREFIX="arm-poky-linux-gnueabi-"
	PATH=${PATH_ARM}:${PATH}
	;;
    arm64)
	cmd=(${cmd_arm64[*]})
	PREFIX="aarch64-linux-gnu-"
	# PATH=${PATH_ARM}:${PATH}
	;;
    avr32)
	cmd=(${cmd_avr32[*]})
	PREFIX="avr32-linux-"
	PATH=${PATH_AVR32}:${PATH}
	;;
    blackfin)
	cmd=(${cmd_blackfin[*]})
	PREFIX="bfin-uclinux-"
	PATH=${PATH_BFIN}:${PATH}
	;;
    cris)
	cmd=(${cmd_cris[*]})
	PREFIX="cris-linux-"
	PATH=${PATH_CRIS}:${PATH}
	;;
    frv)
	cmd=(${cmd_frv[*]})
	PREFIX="frv-linux-"
	PATH=${PATH_FRV}:${PATH}
	;;
    i386)
	cmd=(${cmd_i386[*]})
	PREFIX="x86_64-poky-linux-"
	PATH=${PATH_X86}:${PATH}
	;;
    ia64)
	cmd=(${cmd_ia64[*]})
	PREFIX="ia64-linux-"
	PATH=${PATH_IA64}:${PATH}
	;;
    m68k)
    	cmd=(${cmd_m68k[*]})
	PREFIX="m68k-linux-"
	PATH=${PATH_M68}:${PATH}
	;;
    m68k_nommu)
	# kludge to work around nommu build problems in the 3.0 kernel
    	cmd=(${cmd_m68k_nommu[*]})
	if [ "${rel}" = "v3.0" ]
	then
		PREFIX="m68k-uclinux-"
		PATH=${PATH_M68_NOMMU}:${PATH}
	else
		PREFIX="m68k-linux-"
		PATH=${PATH_M68}:${PATH}
	fi
	ARCH=m68k
        ;;
    microblaze)
	cmd=(${cmd_microblaze[*]})
	PREFIX="microblaze-linux-"
	PATH=${PATH_MICROBLAZE}:${PATH}
	;;
    mips)
	cmd=(${cmd_mips[*]});
	PREFIX="mips-poky-linux-"
	PATH=${PATH_MIPS}:${PATH}
	;;
    parisc)
	cmd=(${cmd_parisc[*]})
	PREFIX="hppa-linux-"
	PATH=${PATH_PARISC}:${PATH}
	;;
    parisc64)
	cmd=(${cmd_parisc64[*]})
	PREFIX="hppa64-linux-"
	PATH=${PATH_PARISC64}:${PATH}
	ARCH=parisc
	;;
    powerpc)
	cmd=(${cmd_powerpc[*]})
	PREFIX="powerpc64-poky-linux-"
	PATH=${PATH_PPC}:${PATH}
	;;
    sparc32)
	cmd=(${cmd_sparc32[*]})
	PREFIX="sparc64-linux-"
	PATH=${PATH_SPARC}:${PATH}
	;;
    sparc64)
	cmd=(${cmd_sparc64[*]})
	PREFIX="sparc64-linux-"
	PATH=${PATH_SPARC}:${PATH}
	;;
    s390)
	cmd=(${cmd_s390[*]})
	PREFIX="s390x-linux-"
	PATH=${PATH_S390}:${PATH}
	;;
    tile)
	cmd=(${cmd_tile[*]})
	PREFIX="tilegx-linux-"
	PATH=${PATH_TILE}:${PATH}
	;;
    sh)
	cmd=(${cmd_sh[*]})
	PREFIX="sh4-linux-"
	PATH=${PATH_SH4}:${PATH}
	;;
    x86_64)
	cmd=(${cmd_x86_64[*]})
	PREFIX="x86_64-poky-linux-"
	PATH=${PATH_X86}:${PATH}
	;;
    xtensa)
	cmd=(${cmd_xtensa[*]})
	PREFIX="xtensa-linux-"
	PATH=${PATH_XTENSA}:${PATH}
	;;
    um)
	cmd=(${cmd_um[*]})
	PREFIX="x86_64-poky-linux-"
	PATH=${PATH_X86}:${PATH}
	SUBARCH="x86_64"
	;;
    *)
	echo "Unsupported or unspecified architecture ${ARCH}"
	exit 1
	;;
    esac

CROSS=""
if [ "${PREFIX}" != "" ]; then
	CROSS="CROSS_COMPILE=${PREFIX}"
fi

SUBARCH_CMD=""
if [ -n "${SUBARCH}" ]
then
	SUBARCH_CMD="SUBARCH=${SUBARCH}"
fi

maxcmd=$(expr ${#cmd[*]} - 1)
for i in $(seq 0 ${maxcmd})
do
    	echo -n "Building ${ARCH}:${cmd[$i]} ... "
	rm -f .config
	make ${CROSS} ARCH=${ARCH} ${SUBARCH_CMD} ${cmd[$i]} >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
	        echo "failed (config) - skipping"
	 	i=$(expr $i + 1)
	 	continue
	fi
	# run config file fixups if necessary
	if [ ${#fixup[*]} -gt 0 ]; then
	    fmax=$(expr ${#fixup[*]} - 1)
	    for f in $(seq 0 ${fmax})
	    do
	        sed -e "${fixup[$f]}" .config > .config.tmp
	        mv .config.tmp .config
	    done
	fi
	make ${CROSS} ARCH=${ARCH} ${SUBARCH_CMD} oldnoconfig >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
	        echo "failed (oldnoconfig) - skipping"
	 	i=$(expr $i + 1)
	 	continue
	fi
    	builds=$(expr ${builds} + 1)
	make ${CROSS} -j12 ARCH=${ARCH} ${SUBARCH_CMD} >/dev/null 2>/tmp/buildlog.$$
	if [ $? -ne 0 ]; then
	    echo "failed"
	    echo "--------------"
	    echo "Error log:"
	    cat /tmp/buildlog.$$
	    echo "--------------"
    	    errors=$(expr ${errors} + 1)
	else
	    echo "passed"
	fi
	rm -f /tmp/buildlog.$$
done

# Clean up again to conserve disk space

git clean -d -f -x -q

echo
echo "-----------------------"
echo "Total builds: ${builds} Total build errors: ${errors}"
