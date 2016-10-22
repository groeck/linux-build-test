#!/bin/bash

basedir=$(cd $(dirname $0); pwd)
. ${basedir}/stable-build-targets.sh

LOG=/tmp/log.$$
BUILDDIR=/tmp/buildbot-builddir

PATH_ALPHA=/opt/kernel/gcc-4.6.3-nolibc/alpha-linux/bin
PATH_AM33=/opt/kernel/gcc-4.6.3-nolibc/am33_2.0-linux/bin
PATH_ARM=/opt/poky/1.7/sysroots/x86_64-pokysdk-linux/usr/bin/arm-poky-linux-gnueabi
PATH_ARM64=/opt/kernel/aarch64/gcc-5.2/usr/bin
PATH_ARC=/opt/kernel/arc/gcc-4.8.3/usr/bin
PATH_ARCV2=/opt/kernel/arcv2/gcc-4.8.5/usr/bin
PATH_AVR32=/opt/kernel/gcc-4.2.4-nolibc/avr32-linux/bin
PATH_BFIN=/opt/kernel/gcc-4.6.3-nolibc/bfin-uclinux/bin
PATH_C6X=/opt/kernel/gcc-5.2.0/c6x-elf/bin
PATH_CRIS=/opt/kernel/gcc-4.6.3-nolibc/cris-linux/bin
PATH_CRISV32=/opt/kernel/gcc-4.6.3-nolibc/crisv32-linux/bin
PATH_FRV=/opt/kernel/gcc-4.6.3-nolibc/frv-linux/bin
PATH_H8300=/opt/kernel/h8300/gcc-5.1.0/usr/bin
PATH_HEXAGON=/opt/kernel/hexagon/bin
PATH_IA64=/opt/kernel/gcc-4.6.3-nolibc/ia64-linux/bin
PATH_M32R=/opt/kernel/gcc-4.6.3-nolibc/m32r-linux/bin
PATH_M68=/opt/kernel/gcc-4.9.0-nolibc/m68k-linux/bin
PATH_METAG=/opt/kernel/metag/gcc-4.2.4/usr/bin
PATH_MICROBLAZE=/opt/kernel/gcc-4.8.0-nolibc/microblaze-linux/bin
PATH_MIPS_22=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/mips32-poky-linux
PATH_MIPS_24=/opt/kernel/gcc-4.9.0-nolibc/mips-linux/bin
PATH_MIPS_25=/opt/poky/2.0/sysroots/x86_64-pokysdk-linux/usr/bin/mips-poky-linux
PATH_NIOS2=/opt/sourceryg++-2014.05/bin
PATH_OPENRISC=/opt/kernel/gcc-4.5.1-nolibc/or32-linux/bin
PATH_PARISC=/opt/kernel/gcc-4.6.3-nolibc/hppa-linux/bin
PATH_PARISC64=/opt/kernel/gcc-4.9.0-nolibc/hppa64-linux/bin
PATH_PPC=/opt/poky/1.6/sysroots/x86_64-pokysdk-linux/usr/bin/powerpc64-poky-linux
PATH_SCORE=/opt/kernel/score/bin
PATH_S390=/opt/kernel/gcc-4.6.3-nolibc/s390x-linux/bin
PATH_SH4=/opt/kernel/sh4/gcc-5.3.0/usr/bin
PATH_SPARC=/opt/kernel/gcc-4.6.3-nolibc/sparc64-linux/bin
PATH_TILE=/opt/kernel/gcc-4.6.2-nolibc/tilegx-linux/bin
PATH_UC32=/opt/kernel/unicore32/uc4-1.0.5-hard/bin
PATH_X86=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/x86_64-poky-linux
PATH_XTENSA=/opt/kernel/xtensa/gcc-4.7.3/usr/bin

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
relx=$(echo ${rel} | sed -e 's/\.//' | sed -e 's/v//')
branch=$(git branch | cut -f2 -d' ')

maxload=$(($(nproc) + 4))

errors=0
builds=0

ref=$(git describe)
echo
echo "Build reference: ${ref}"
echo

ARCH=$1
BRANCH=$2

# clean up source directory expected to be done by caller
# Do it again to be able to call script directly.
git clean -x -f -d -q

tmp=skip_${relx}
skip=(${!tmp})

SUBARCH=""
EXTRA_CMD=""
declare -a fixup
case ${ARCH} in
    alpha)
	cmd=(${cmd_alpha[*]})
	fmax=$(expr ${#fixup_alpha[*]} - 1)
	for f in $(seq 0 ${fmax})
	do
	    fixup[$f]=${fixup_alpha[$f]}
	done
	PREFIX="alpha-linux-"
	PATH=${PATH_ALPHA}:${PATH}
	EXTRA_CMD="KALLSYMS_EXTRA_PASS=1"
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
    arcv2)
	ARCH=arc
	cmd=(${cmd_arcv2[*]})
	fmax=$(expr ${#fixup_arcv2[*]} - 1)
	for f in $(seq 0 ${fmax})
	do
	    fixup[$f]=${fixup_arcv2[$f]}
	done
	PREFIX="arc-linux-"
	PATH=${PATH_ARCV2}:${PATH}
	;;
    arm)
	cmd=(${cmd_arm[*]})
	PREFIX="arm-poky-linux-gnueabi-"
	PATH=${PATH_ARM}:${PATH}
	EXTRA_CMD="KALLSYMS_EXTRA_PASS=1"
	;;
    arm64)
	cmd=(${cmd_arm64[*]})
	PREFIX="aarch64-linux-"
	PATH=${PATH_ARM64}:${PATH}
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
    c6x)
	cmd=(${cmd_c6x[*]})
	PREFIX="c6x-elf-"
	# PREFIX="tic6x-uclinux-"
	PATH=${PATH_C6X}:${PATH}
	;;
    crisv32)
	ARCH=cris
	cmd=(${cmd_crisv32[*]})
	PREFIX="crisv32-linux-"
	PATH=${PATH_CRISV32}:${PATH}
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
    h8300)
	cmd=(${cmd_h8300[*]})
	PREFIX="h8300-elf-linux-newlib-"
	PATH=${PATH_H8300}:${PATH}
	;;
    hexagon)
	cmd=(${cmd_hexagon[*]})
	PREFIX="hexagon-linux-"
	PATH=${PATH_HEXAGON}:${PATH}
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
    m32r)
	cmd=(${cmd_m32r[*]})
	PREFIX="m32r-linux-"
	PATH=${PATH_M32R}:${PATH}
	;;
    m68k)
    	cmd=(${cmd_m68k[*]})
	PREFIX="m68k-linux-"
	PATH=${PATH_M68}:${PATH}
	;;
    m68k_nommu)
    	cmd=(${cmd_m68k_nommu[*]})
	PREFIX="m68k-linux-"
	PATH=${PATH_M68}:${PATH}
	ARCH=m68k
        ;;
    metag)
	cmd=(${cmd_metag[*]})
	PREFIX="metag-unknown-linux-uclibc-"
	PATH=${PATH_METAG}:${PATH}
	;;
    microblaze)
	cmd=(${cmd_microblaze[*]})
	PREFIX="microblaze-linux-"
	PATH=${PATH_MICROBLAZE}:${PATH}
	;;
    mips_22)
	ARCH=mips
	cmd=(${cmd_mips_22[*]});
	fmax=$(expr ${#fixup_mips[*]} - 1)
	for f in $(seq 0 ${fmax})
	do
	    fixup[$f]=${fixup_mips[$f]}
	done
	PREFIX="mips-poky-linux-"
	PATH=${PATH_MIPS_22}:${PATH}
	;;
    mips_24)
	ARCH=mips
	cmd=(${cmd_mips_24[*]});
	fmax=$(expr ${#fixup_mips[*]} - 1)
	for f in $(seq 0 ${fmax})
	do
	    fixup[$f]=${fixup_mips[$f]}
	done
	PREFIX="mips-linux-"
	PATH=${PATH_MIPS_24}:${PATH}
	;;
    mips_25)
	ARCH=mips
	cmd=(${cmd_mips_25[*]});
	fmax=$(expr ${#fixup_mips[*]} - 1)
	for f in $(seq 0 ${fmax})
	do
	    fixup[$f]=${fixup_mips[$f]}
	done
	PREFIX="mips-poky-linux-"
	PATH=${PATH_MIPS_25}:${PATH}
	;;
    mn10300)
	cmd=(${cmd_mn10300[*]})
	PREFIX="am33_2.0-linux-"
	PATH=${PATH_AM33}:${PATH}
	;;
    nios2)
	cmd=(${cmd_nios2[*]})
	PREFIX="nios2-linux-gnu-"
	PATH=${PATH_NIOS2}:${PATH}
	;;
    openrisc)
	cmd=(${cmd_openrisc[*]})
	PREFIX="or32-linux-"
	PATH=${PATH_OPENRISC}:${PATH}
	;;
    parisc)
	cmd=(${cmd_parisc[*]})
	PREFIX="hppa-linux-"
	PATH=${PATH_PARISC}:${PATH}
	;;
    parisc64)
	cmd=(${cmd_parisc64[*]})
	fmax=$(expr ${#fixup_parisc64[*]} - 1)
	for f in $(seq 0 ${fmax})
	do
	    fixup[$f]=${fixup_parisc64[$f]}
	done
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
    score)
	cmd=(${cmd_score[*]})
	PREFIX="score-elf-"
	PATH=${PATH_SCORE}:${PATH}
	;;
    tile)
	cmd=(${cmd_tile[*]})
	fmax=$(expr ${#fixup_tile[*]} - 1)
	for f in $(seq 0 ${fmax})
	do
	    fixup[$f]=${fixup_tile[$f]}
	done
	PREFIX="tilegx-linux-"
	PATH=${PATH_TILE}:${PATH}
	;;
    sh)
	cmd=(${cmd_sh[*]})
	PREFIX="sh4-linux-"
	PATH=${PATH_SH4}:${PATH}
	;;
    unicore32)
	cmd=(${cmd_unicore32[*]})
	PREFIX="unicore32-linux-"
	PATH=${PATH_UC32}:${PATH}
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
	fmax=$(expr ${#fixup_xtensa[*]} - 1)
	for f in $(seq 0 ${fmax})
	do
	    fixup[$f]=${fixup_xtensa[$f]}
	done
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

if [ -n "${SUBARCH}" ]
then
	EXTRA_CMD="${EXTRA_CMD} SUBARCH=${SUBARCH}"
fi

if [ ${#fixup[*]} -gt 0 ]; then
    echo "Configuration file workarounds:"
    fmax=$(expr ${#fixup[*]} - 1)
    for f in $(seq 0 ${fmax})
    do
        echo "    ${fixup[$f]}"
    done
    echo
fi

rm -rf ${BUILDDIR}
mkdir -p ${BUILDDIR}

maxcmd=$(expr ${#cmd[*]} - 1)
for i in $(seq 0 ${maxcmd})
do
	build="${ARCH}:${cmd[$i]}"

	echo -n "Building ${build} ... "
	for s in ${skip[*]}
	do
	    if [ "$s" = "${build}" ]
	    then
		echo "failed (script) - skipping"
		continue 2
	    fi
	done

	rm -f .config
	make ${CROSS} ARCH=${ARCH} O=${BUILDDIR} ${EXTRA_CMD} ${cmd[$i]} >/dev/null 2>&1
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
	        sed -i -e "${fixup[$f]}" ${BUILDDIR}/.config
	    done
	fi

	# Run branch specific initialization if necessary
	if [ -n "${BRANCH}" -a -x "${basedir}/branches/${BRANCH}/setup.sh" ]
	then
		. ${basedir}/branches/${BRANCH}/setup.sh ${ARCH} ${BRANCH} ${BUILDDIR}
	fi

	make ${CROSS} ARCH=${ARCH} O=${BUILDDIR} ${EXTRA_CMD} oldnoconfig >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
	        echo "failed (oldnoconfig) - skipping"
	 	i=$(expr $i + 1)
	 	continue
	fi
    	builds=$(expr ${builds} + 1)
	make ${CROSS} -j${maxload} ARCH=${ARCH} O=${BUILDDIR} ${EXTRA_CMD} >/dev/null 2>/tmp/buildlog.$$
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

rm -rf ${BUILDDIR}

# Clean up again to conserve disk space
# git clean -d -f -x -q

echo
echo "-----------------------"
echo "Total builds: ${builds} Total build errors: ${errors}"
