#!/bin/bash

basedir=$(cd $(dirname $0); pwd)
. ${basedir}/stable-build-targets.sh

PATH_ALPHA=/opt/kernel/gcc-8.1.0-nolibc/alpha-linux/bin
PATH_AM33=/opt/kernel/gcc-4.6.3-nolibc/am33_2.0-linux/bin
PATH_ARM=/opt/kernel/gcc-7.3.0-nolibc/arm-linux-gnueabi/bin
PATH_ARM64=/opt/kernel/gcc-7.3.0-nolibc/aarch64-linux/bin
# arc images don't build with gcc 8.1.0 / 7.3.0 from kernel.org
PATH_ARC=/opt/kernel/arc/gcc-7.3.0/usr/bin
PATH_ARCV2=/opt/kernel/arcv2/gcc-8.2.0/usr/bin
PATH_BFIN=/opt/kernel/gcc-4.6.3-nolibc/bfin-uclinux/bin
PATH_C6X=/opt/kernel/gcc-8.1.0-nolibc/c6x-elf/bin
PATH_CRIS=/opt/kernel/gcc-4.6.3-nolibc/cris-linux/bin
PATH_CRISV32=/opt/kernel/gcc-4.6.3-nolibc/crisv32-linux/bin
PATH_CSKY=/opt/kernel/csky/gcc-6.3.0/bin
PATH_FRV=/opt/kernel/gcc-4.6.3-nolibc/frv-linux/bin
PATH_H8300=/opt/kernel/gcc-8.1.0-nolibc/h8300-linux/bin
PATH_HEXAGON=/opt/kernel/hexagon/bin
PATH_IA64=/opt/kernel/gcc-8.1.0-nolibc/ia64-linux/bin
PATH_M32R=/opt/kernel/gcc-4.6.3-nolibc/m32r-linux/bin
PATH_M68=/opt/kernel/gcc-7.3.0-nolibc/m68k-linux/bin
PATH_METAG=/opt/kernel/metag/gcc-4.2.4/usr/bin
PATH_MICROBLAZE=/opt/kernel/microblaze/gcc-6.4.0/bin
PATH_MIPS=/opt/kernel/gcc-7.3.0-nolibc/mips64-linux/bin
PATH_NDS32=/opt/kernel/gcc-8.1.0-nolibc/nds32le-linux/bin
PATH_NIOS2=/opt/kernel/gcc-7.3.0-nolibc/nios2-linux/bin
PATH_OPENRISC_45=/opt/kernel/gcc-4.5.1-nolibc/or32-linux/bin
PATH_OPENRISC=/opt/kernel/gcc-7.3.0-nolibc/or1k-linux/bin
PATH_PARISC=/opt/kernel/gcc-8.1.0-nolibc/hppa-linux/bin
PATH_PARISC64=/opt/kernel/gcc-8.1.0-nolibc/hppa64-linux/bin
# 6.4.0, 6.5.0 internal compiler error in fs/exofs/dir.o -next after 4.20
# 7.3.0 hangs on ppc64 allnoconfig builds (4.14, 4.16) when building kernel/cpu.o
# 8.2.0 generates build errors (overzaelous compiler)
PATH_PPC=/opt/kernel/powerpc64/gcc-7.4.0/bin
PATH_RISCV64=/opt/kernel/gcc-7.3.0-nolibc/riscv64-linux/bin
PATH_SCORE=/opt/kernel/score/bin
PATH_S390=/opt/kernel/gcc-7.3.0-nolibc/s390-linux/bin
PATH_SH4=/opt/kernel/gcc-8.1.0-nolibc/sh4-linux/bin
# sparc images don't build with gcc 8.1.0
PATH_SPARC=/opt/kernel/gcc-7.3.0-nolibc/sparc64-linux/bin
PATH_TILE=/opt/kernel/gcc-4.6.2-nolibc/tilegx-linux/bin
PATH_UC32=/opt/kernel/unicore32/uc4-1.0.5-hard/bin
PATH_X86=/opt/kernel/x86_64/gcc-8.2.0/usr/bin/
PATH_XTENSA=/opt/kernel/xtensa/gcc-7.2.0/usr/bin

PREFIX_ARC="arc-linux-"
PREFIX_ARM="arm-linux-gnueabi-"
PREFIX_PPC=powerpc64-linux-
PREFIX_S390="s390-linux-"
PREFIX_X86="x86_64-linux-"

BUILDDIR="$(mktemp -d /tmp/buildbot-builddir.XXXXX)"
LOG="$(mktemp /tmp/buildlog.XXXXX)"

trap __cleanup EXIT SIGHUP SIGINT SIGQUIT SIGILL SIGTRAP SIGABRT

__cleanup()
{
    rv=$?
    rm -rf ${BUILDDIR} ${LOG}
    exit ${rv}
}

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
relx=$(echo ${rel} | sed -e 's/\.//' | sed -e 's/v//')
branch=$(git branch | cut -f2 -d' ')

configcmd="olddefconfig"

# Older releases don't like gcc 6+
case ${rel} in
v3.16|v3.18)
	# lib/mpi/longlong.h:651:2: error: impossible constraint in 'asm'
	# with gcc 5.1 and later
	PATH_MIPS=/opt/kernel/gcc-4.9.4-nolibc/mips64-linux/bin
	# Various errors and warnings with more recent compilers
	# (including gcc 7.3.0)
	PATH_ALPHA=/opt/kernel/gcc-6.4.0-nolibc/alpha-linux/bin
	# arc needs old gcc up to v4.1.y (up to commit a6416f57ce57)
	PATH_ARC=/opt/kernel/arc/gcc-4.8.3/usr/bin
	# ppc needs old compiler up to and including v3.18
	# (see commit c2ce6f9f3dc0)
	PATH_PPC=/opt/kernel/gcc-4.7.3-nolibc/powerpc64-linux/bin
	PATH_S390=/opt/kernel/s390/gcc-6.4.0/bin
	# sh4 supports recent compilers only starting with v4.4
	# (see commit 940d4113f330). Note that we can't use the kernel.org
	# toolchain for gcc 5.5.0 either; it results in "'-m4-nofpu' is not
	# supported ...".
	PATH_SH4=/opt/kernel/sh4/gcc-5.3.0/usr/bin
	# sparc images prior to v4.9 don't build with gcc 7+
	# (see commit 0fde7ad71ee3, 009615ab7fd4, and more)
	PATH_SPARC=/opt/kernel/gcc-6.4.0-nolibc/sparc64-linux/bin
	if [[ "${rel}" = "v3.16" ]]; then
	    # x86 has build errors with gcc 8.2.0 on v3.16, both i386 and x86_64
	    PATH_X86=/opt/kernel/x86_64/gcc-6.3.0/usr/bin/
	fi
	;;
v4.4)
	PATH_SPARC=/opt/kernel/gcc-6.4.0-nolibc/sparc64-linux/bin
	;;
*)
	;;
esac

maxload=$(($(nproc) * 3 / 2))

errors=0
builds=0

ref=$(git describe)
echo
echo "Build reference: ${ref}"

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
	PREFIX="alpha-linux-"
	PATH=${PATH_ALPHA}:${PATH}
	EXTRA_CMD="KALLSYMS_EXTRA_PASS=1"
	;;
    arc)
	cmd=(${cmd_arc[*]})
	PREFIX="${PREFIX_ARC}"
	# Original path first to pick up bison
	PATH=${PATH}:${PATH_ARC}
	;;
    arcv2)
	ARCH=arc
	cmd=(${cmd_arcv2[*]})
	PREFIX="arc-linux-"
	# Original path first to pick up bison
	PATH=${PATH}:${PATH_ARCV2}
	;;
    arm)
	cmd=(${cmd_arm[*]})
	PREFIX=${PREFIX_ARM}
	PATH=${PATH_ARM}:${PATH}
	EXTRA_CMD="KALLSYMS_EXTRA_PASS=1"
	;;
    arm64)
	cmd=(${cmd_arm64[*]})
	PREFIX="aarch64-linux-"
	PATH=${PATH_ARM64}:${PATH}
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
    csky)
	cmd=(${cmd_csky[*]})
	PREFIX="csky-linux-"
	PATH=${PATH_CSKY}:${PATH}
	;;
    frv)
	cmd=(${cmd_frv[*]})
	PREFIX="frv-linux-"
	PATH=${PATH_FRV}:${PATH}
	;;
    h8300)
	cmd=(${cmd_h8300[*]})
	PREFIX="h8300-linux-"
	PATH=${PATH_H8300}:${PATH}
	;;
    hexagon)
	cmd=(${cmd_hexagon[*]})
	PREFIX="hexagon-linux-"
	PATH=${PATH_HEXAGON}:${PATH}
	;;
    i386)
	cmd=(${cmd_i386[*]})
	PREFIX=${PREFIX_X86}
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
    mips)
	cmd=(${cmd_mips[*]});
	PREFIX="mips64-linux-"
	PATH=${PATH_MIPS}:${PATH}
	;;
    mn10300)
	cmd=(${cmd_mn10300[*]})
	PREFIX="am33_2.0-linux-"
	PATH=${PATH_AM33}:${PATH}
	;;
    nds32)
	cmd=(${cmd_nds32[*]})
	PREFIX="nds32le-linux-"
	PATH=${PATH_NDS32}:${PATH}
	;;
    nios2)
	cmd=(${cmd_nios2[*]})
	PREFIX="nios2-linux-"
	PATH=${PATH_NIOS2}:${PATH}
	;;
    openrisc)
	cmd=(${cmd_openrisc[*]})
	case ${rel} in
	v3.16|v3.18|v4.4|v4.9)
		PREFIX="or32-linux-"
		PATH=${PATH_OPENRISC_45}:${PATH}
		;;
	*)
		PREFIX="or1k-linux-"
		PATH=${PATH_OPENRISC}:${PATH}
		;;
	esac
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
	PREFIX="${PREFIX_PPC}"
	PATH=${PATH_PPC}:${PATH}
	;;
    riscv)
	cmd=(${cmd_riscv[*]})
	PREFIX="riscv64-linux-"
	PATH=${PATH_RISCV64}:${PATH}
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
	PREFIX=${PREFIX_S390}
	PATH=${PATH_S390}:${PATH}
	;;
    score)
	cmd=(${cmd_score[*]})
	PREFIX="score-elf-"
	PATH=${PATH_SCORE}:${PATH}
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
    unicore32)
	cmd=(${cmd_unicore32[*]})
	PREFIX="unicore32-linux-"
	PATH=${PATH_UC32}:${PATH}
	;;
    x86_64)
	cmd=(${cmd_x86_64[*]})
	PREFIX=${PREFIX_X86}
	PATH=${PATH_X86}:${PATH}
	;;
    xtensa)
	cmd=(${cmd_xtensa[*]})
	PREFIX="xtensa-linux-"
	PATH=${PATH_XTENSA}:${PATH}
	;;
    um)
	cmd=(${cmd_um[*]})
	case ${rel} in
	v3.16)
		# um fails to build with more recent compilers
		PATH_X86=/opt/kernel/gcc-4.8.5-nolibc/x86_64-linux/bin
		PREFIX="${PREFIX_X86}"
		;;
	v3.18|v4.4|v4.9|v4.14|v4.19)
		# doesn't build with 8.2.0 ("virtual memory exhausted")
		PATH_X86=/opt/kernel/x86_64/gcc-6.3.0/usr/bin
		PREFIX="${PREFIX_X86}"
		;;
	*)
		PREFIX="${PREFIX_X86}"
		;;
	esac
	PATH=${PATH_X86}:${PATH}
	SUBARCH="x86_64"
	;;
    *)
	echo "Unsupported or unspecified architecture ${ARCH}"
	exit 1
	;;
esac

tmp="fixup_${ARCH}[@]"
if [[ -n "${!tmp}" ]]; then
    fixup+=("${!tmp}")
fi

tmp="fixup_${ARCH}_${relx}[@]"
if [[ -n "${!tmp}" ]]; then
    fixup+=("${!tmp}")
fi

echo "gcc version: $(${PREFIX}gcc --version | grep gcc)"
echo

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
        echo "    \"${fixup[$f]}\""
    done
    echo
fi

rm -rf "${BUILDDIR}/*"

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

	# perf build is special. Use host gcc and build based on defconfig.
	if [[ "${cmd[$i]}" = "tools/perf" ]]; then
	    if ! make ARCH=${ARCH} O=${BUILDDIR} defconfig >/dev/null 2>${LOG}; then
		echo "failed"
		echo "--------------"
		echo "Error log:"
		cat ${LOG}
		echo "--------------"
		continue
	    fi
	    case ${rel} in
		    "v3.16"|"v3.18")
			cd "${cmd[$i]}"
			make ARCH=${ARCH} WERROR=0 O="${BUILDDIR}" >/dev/null 2>${LOG}
			rv=$?
			cd ../..
			;;
		    *)
			make ARCH=${ARCH} O=${BUILDDIR} "${cmd[$i]}" >/dev/null 2>${LOG}
			rv=$?
			;;
	    esac
	    if [ ${rv} -ne 0 ]; then
		    echo "failed"
		    echo "--------------"
		    echo "Error log:"
		    cat ${LOG}
		    echo "--------------"
		    errors=$(expr ${errors} + 1)
	    else
		    echo "passed"
	    fi
	    i=$(expr $i + 1)
	    continue
	fi

	if ! make ${CROSS} ARCH=${ARCH} O=${BUILDDIR} ${EXTRA_CMD} ${cmd[$i]} >${LOG} 2>&1; then
	    # Only report an error if the default configuration
	    # does not exist.
	    if grep -q "No rule to make target" ${LOG}; then
	        echo "failed (config) - skipping"
	    elif grep -q "Can't find default configuration" ${LOG}; then
	        echo "failed (config) - skipping"
	    else
	        echo "failed"
		echo "--------------"
		echo "Error log:"
		cat ${LOG}
		echo "--------------"
	    fi
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

	make ${CROSS} ARCH=${ARCH} O=${BUILDDIR} ${EXTRA_CMD} "${configcmd}" >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
	        echo "failed (${configcmd}) - skipping"
	 	i=$(expr $i + 1)
	 	continue
	fi
    	builds=$(expr ${builds} + 1)
	# Auto-repeat a few times to handle internal compiler errors
	# [Ryzen problem]
	n=0
	while true
	do
	  make ${CROSS} -j${maxload} ARCH=${ARCH} O=${BUILDDIR} ${EXTRA_CMD} >/dev/null 2>${LOG}
	  if [ $? -eq 0 ]
	  then
	    echo "passed"
	    break
	  fi
	  grep -q -e "internal compiler error|Segmentation fault" ${LOG}
	  if [ $? -ne 0 -o $n -gt 2 ]
	  then
	    echo "failed"
	    echo "--------------"
	    echo "Error log:"
	    cat ${LOG}
	    echo "--------------"
	    errors=$(expr ${errors} + 1)
	    break
	  fi
	  n=$(expr $n + 1)
	done
done

# Clean up again to conserve disk space
git clean -d -f -x -q

echo
echo "-----------------------"
echo "Total builds: ${builds} Total build errors: ${errors}"
