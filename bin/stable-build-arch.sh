#!/bin/bash

basedir=$(cd $(dirname $0); pwd)
. ${basedir}/stable-build-targets.sh

# default compiler version
CV="11.2.0"

PATH_ALPHA=/opt/kernel/gcc-${CV}-nolibc/alpha-linux/bin
# with gcc 10.3.0,11.1.0 in v4.14.y:
# am33_2.0-linux-ld: am33_2.0-linux-ld: DWARF error: mangled line number section
# PATH_AM33=/opt/kernel/gcc-${CV}-nolibc/am33_2.0-linux/bin
PATH_AM33=/opt/kernel/gcc-9.4.0-nolibc/am33_2.0-linux/bin
PATH_ARM=/opt/kernel/gcc-${CV}-nolibc/arm-linux-gnueabi/bin
PATH_ARM64=/opt/kernel/gcc-${CV}-nolibc/aarch64-linux/bin
PATH_ARC=/opt/kernel/gcc-${CV}-nolibc/arc-linux/bin
PATH_ARCV2=/opt/kernel/gcc-${CV}-nolibc/arcv2-linux/bin
PATH_BFIN=/opt/kernel/gcc-${CV}-nolibc/bfin-uclinux/bin
# ICE with gcc 9.2.0, gcc 9.3.0, gcc 10.3.0
# Assembler errors with gcc 8.4.0, 8.5.0 (v4.14.y, v4.19.y)
# on v4.4.y (at least), in kernel/fork.c:
# "unrecognized emulation mode: big-endian" with gcc 10.2.0
# internal compiler error with gcc 11.1.0 (4.4.y, 4.9.y)
# PATH_C6X=/opt/kernel/gcc-${CV}-nolibc/c6x-elf/bin
PATH_C6X=/opt/kernel/gcc-8.3.0-nolibc/c6x-elf/bin
# No cris support in gcc 10.x.
PATH_CRIS=/opt/kernel/gcc-9.4.0-nolibc/cris-linux/bin
PATH_CRISV32=/opt/kernel/gcc-4.6.3-nolibc/crisv32-linux/bin
PATH_CSKY=/opt/kernel/gcc-${CV}-nolibc/csky-linux/bin
PATH_FRV=/opt/kernel/gcc-${CV}-nolibc/frv-linux/bin
PATH_H8300=/opt/kernel/gcc-${CV}-nolibc/h8300-linux/bin
PATH_HEXAGON=/opt/kernel/hexagon/bin
PATH_IA64=/opt/kernel/gcc-${CV}-nolibc/ia64-linux/bin
PATH_M32R=/opt/kernel/gcc-${CV}-nolibc/m32r-linux/bin
PATH_M68=/opt/kernel/gcc-${CV}-nolibc/m68k-linux/bin
PATH_METAG=/opt/kernel/metag/gcc-4.2.4/usr/bin
PATH_MICROBLAZE=/opt/kernel/gcc-${CV}-nolibc/microblaze-linux/bin
PATH_MIPS=/opt/kernel/gcc-${CV}-nolibc/mips64-linux/bin
# gcc-8.{2,3,4,5}.0 don't compile for nds32.
# gcc-9.x/10.x//11.x: assembler errors when compiling allmodconfig
# PATH_NDS32=/opt/kernel/gcc-${CV}-nolibc/nds32le-linux/bin
PATH_NDS32=/opt/kernel/gcc-8.1.0-nolibc/nds32le-linux/bin
PATH_NIOS2=/opt/kernel/gcc-${CV}-nolibc/nios2-linux/bin
PATH_OPENRISC_45=/opt/kernel/gcc-4.5.1-nolibc/or32-linux/bin
PATH_OPENRISC=/opt/kernel/gcc-${CV}-nolibc/or1k-linux/bin
PATH_PARISC=/opt/kernel/gcc-${CV}-nolibc/hppa-linux/bin
PATH_PARISC64=/opt/kernel/gcc-${CV}-nolibc/hppa64-linux/bin
# gcc 11.2.0/binutils 2.37:
# Cannot find symbol for section 11: .text.unlikely in kernel/kexec_file.o
PATH_PPC=/opt/kernel/gcc-11.2.0-2.36.1-nolibc/powerpc64-linux/bin
PATH_RISCV64=/opt/kernel/gcc-${CV}-nolibc/riscv64-linux/bin
PATH_RISCV32=/opt/kernel/gcc-${CV}-nolibc/riscv32-linux/bin
PATH_SCORE=/opt/kernel/score/bin
PATH_S390=/opt/kernel/gcc-${CV}-nolibc/s390-linux/bin
PATH_SH4=/opt/kernel/gcc-${CV}-nolibc/sh4-linux/bin
# gcc 11.x:
# arch/sparc/kernel/mdesc.c:404:22: error: 'strcmp' reading 1 or more bytes from a region of size 0
# with all kernels v4.9.x and later
# PATH_SPARC=/opt/kernel/gcc-${CV}-nolibc/sparc64-linux/bin
PATH_SPARC=/opt/kernel/gcc-10.3.0-nolibc/sparc64-linux/bin
PATH_TILE=/opt/kernel/gcc-4.6.2-nolibc/tilegx-linux/bin
PATH_X86=/opt/kernel/gcc-${CV}-nolibc/x86_64-linux/bin
PATH_XTENSA=/opt/kernel/gcc-${CV}-nolibc/xtensa-linux/bin

PATH_LLVM=/opt/kernel/clang+llvm-12.0.0-x86_64-linux-gnu-ubuntu-16.04/bin

PREFIX_ARC="arc-elf-"
PREFIX_ARCV2="arc-elf-"
PREFIX_ARM="arm-linux-gnueabi-"
PREFIX_PPC=powerpc64-linux-
PREFIX_S390="s390-linux-"
PREFIX_X86="x86_64-linux-"

BUILDDIR="/tmp/buildbot-builddir"
LOG="/tmp/buildlog.stable-build-arch"

trap __cleanup EXIT SIGHUP SIGINT SIGQUIT SIGILL SIGTRAP SIGABRT SIGBUS SIGFPE SIGSEGV SIGALRM SIGTERM SIGPWR

__cleanup()
{
    rv=$?
    rm -rf ${BUILDDIR} ${LOG}
    exit ${rv}
}

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
relx=$(echo ${rel} | sed -e 's/\.//' | sed -e 's/v//')
branch=$(git branch | cut -f2 -d' ')

# Limit file size to ~3.5 GB to prevent log file sizes from getting
# out of control while at the same time supporting large images
# (x86_64/allyesconfig: above 1GB, cris/defconfig: 3.2GB).
ulimit -f $((3500*1024))

configcmd="olddefconfig"

# Older releases don't like gcc 6+
case ${rel} in
v4.4)
	# 9.2.0 array subscript out of bounds in arch/powerpc/lib/feature-fixups.c
	# Don't touch version; other compiler versions have various issues.
	PATH_PPC=/opt/kernel/powerpc64/gcc-7.4.0/bin
	# sparc images prior to v4.9 don't build with gcc 7+
	# (see commit 0fde7ad71ee3, 009615ab7fd4, and more)
	PATH_SPARC=/opt/kernel/gcc-6.4.0-nolibc/sparc64-linux/bin
	# S390 needs gcc 8.x or older for kernels prior to v5.0.
	# See kernel commit 146448524bdd ("s390/jump_label: Use "jdd"
	# constraint on gcc9") for details.
	PATH_S390=/opt/kernel/gcc-8.5.0-nolibc/s390-linux/bin
	;;
v4.9)
	# 9.2.0 array subscript out of bounds in arch/powerpc/lib/feature-fixups.c
	PATH_PPC=/opt/kernel/powerpc64/gcc-7.4.0/bin
	PATH_S390=/opt/kernel/gcc-8.5.0-nolibc/s390-linux/bin
	;;
v4.14|v4.19)
	PATH_S390=/opt/kernel/gcc-8.5.0-nolibc/s390-linux/bin
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
BUILDARCH="${ARCH}"
BRANCH=$2

# clean up source directory expected to be done by caller
# Do it again to be able to call script directly.
git clean -x -f -d -q

tmp=skip_${relx}
skip=(${!tmp})

SUBARCH=""
EXTRA_CMD=""
CCMD=""
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
	PREFIX="${PREFIX_ARCV2}"
	# Original path first to pick up bison
	PATH=${PATH}:${PATH_ARCV2}
	# PATH=${PATH}:${PATH_ARC}
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
	case ${rel} in
	v4.4|v4.9|v4.14|v4.19|v5.4)
	    PREFIX="hexagon-linux-"
	    PATH=${PATH_HEXAGON}:${PATH}
	    ;;
	*)
	    PREFIX="hexagon-unknown-linux-gnu-"
	    PATH=${PATH_LLVM}:${PATH}
	    CCMD="clang"
	    EXTRA_CMD="CC=clang LLVM=1 LLVM_IAS=1"
	    ;;
	esac
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
	EXTRA_CMD="KALLSYMS_EXTRA_PASS=1"
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
	v4.4|v4.9)
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
	# EXTRA_CMD="KALLSYMS_EXTRA_PASS=1"
	;;
    riscv)
	cmd=(${cmd_riscv[*]})
	PREFIX="riscv64-linux-"
	PATH=${PATH_RISCV64}:${PATH}
	;;
    riscv32)
	ARCH=riscv
	cmd=(${cmd_riscv[*]})
	PREFIX="riscv32-linux-"
	PATH=${PATH_RISCV32}:${PATH}
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
	v4.4|v4.9|v4.14|v4.19)
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

if [[ "${CCMD}" = "clang" ]]; then
    compiler_version="$(clang --version | grep 'clang version')"
else
    compiler_version="$(${PREFIX}gcc --version | grep gcc)"
fi

echo "Compiler version: ${compiler_version}"
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

rm -rf "${BUILDDIR}"

dumplog()
{
    local maxsize="$1"
    local log="$2"
    local logsize="$(cat ${log} | wc -l)"

    # strip off path name - it is irrelevant for the log
    local basedir="$(pwd | sed -e 's/\//\\\//g')\/"
    sed -i -e "s/${basedir}//" "${log}"

    # Empty lines are irrelevant / don't add value.
    sed -i -e '/^$/d' "${log}"

    echo "--------------"
    echo "Error log:"
    if [[ ${logsize} -lt ${maxsize} ]]; then
	cat "${log}"
    else
	local splitsize=$((maxsize / 3))
	head "-${splitsize}" "${log}"
	echo "..."
	echo "[skipped]"
	echo "..."
	tail "-${splitsize}" "${log}"
    fi
    echo "--------------"
}

maxcmd=$(expr ${#cmd[*]} - 1)
for i in $(seq 0 ${maxcmd})
do
	build="${BUILDARCH}:${cmd[$i]}"

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

	# perf build is special. Use host compiler and build based on defconfig.
	if [[ "${cmd[$i]}" = "tools/perf" ]]; then
	    if ! make ARCH=${ARCH} O=${BUILDDIR} defconfig >/dev/null 2>${LOG}; then
		echo "failed (config)"
		dumplog 100 "${LOG}"
		continue
	    fi
	    make ARCH=${ARCH} O=${BUILDDIR} "${cmd[$i]}" >/dev/null 2>${LOG}
	    rv=$?
	    if [ ${rv} -ne 0 ]; then
		    echo "failed"
		    dumplog 1000 "${LOG}"
		    errors=$(expr ${errors} + 1)
	    else
		    echo "passed"
	    fi
	    i=$(expr $i + 1)
	    continue
	fi

	if ! make ${CROSS} ARCH=${ARCH} O=${BUILDDIR} ${EXTRA_CMD} ${cmd[$i]} </dev/null >${LOG} 2>&1; then
	    # Only report an error if the default configuration
	    # does not exist.
	    if grep -q "No rule to make target" ${LOG}; then
	        echo "failed (config) - skipping"
	    elif grep -q "Can't find default configuration" ${LOG}; then
	        echo "failed (config) - skipping"
	    else
	        echo "failed (config)"
		dumplog 100 "${LOG}"
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

	# Always disable CONFIG_WERROR.
	# Commit 3fe617ccafd6 ("Enable '-Werror' by default for all kernel
	# builds") enables -Werror for all builds, causing a large number
	# of failures for both compile and boot test images. This hides real
	# compile and boot failures and thus isn't useful for this testbed.
	# Disable it.

	# Temporary: Let's see if the problems get resolved.
	# Uncomment if the situation does not improve by v5.15.
	# sed -i -e 's/CONFIG_WERROR=y/# CONFIG_WERROR is not set/' ${BUILDDIR}/.config

	# Run branch specific initialization if necessary
	if [ -n "${BRANCH}" -a -x "${basedir}/branches/${BRANCH}/setup.sh" ]
	then
	    . ${basedir}/branches/${BRANCH}/setup.sh ${ARCH} ${BRANCH} ${BUILDDIR}
	fi

	if ! make ${CROSS} ARCH=${ARCH} O=${BUILDDIR} ${EXTRA_CMD} "${configcmd}" </dev/null >/dev/null 2>&1; then
	    echo "failed (${configcmd}) - skipping"
	    i=$(expr $i + 1)
	    continue
	fi
    	builds=$(expr ${builds} + 1)
	if ! make ${CROSS} -j${maxload} ARCH=${ARCH} O=${BUILDDIR} ${EXTRA_CMD} </dev/null >/dev/null 2>"${LOG}"; then
	    if grep -q "CONFIG_WERROR=y" ${BUILDDIR}/.config; then
		# If this was a test build, repeat and report _all_ errors.
		make ${CROSS} -i -j${maxload} ARCH=${ARCH} O=${BUILDDIR} ${EXTRA_CMD} </dev/null >/dev/null 2>"${LOG}"
	    fi
	    echo "failed"
	    dumplog 3000 "${LOG}"
	    errors=$(expr ${errors} + 1)
	else
	    echo "passed"
	fi
done

# Clean up again to conserve disk space
git clean -d -f -x -q
rm -rf "${BUILDDIR}" "${LOG}"

echo
echo "-----------------------"
echo "Total builds: ${builds} Total build errors: ${errors}"
