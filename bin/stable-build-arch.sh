#!/bin/bash

basedir=$(cd $(dirname $0); pwd)
. ${basedir}/stable-build-targets.sh
. ${basedir}/build-macros.sh

# default compiler version
CV8="8.5.0"
CV="11.4.0-2.40"
CV12="12.3.0-2.40"
CV13="13.2.0-2.42"

# gcc version to use for building perf
GCC_PERF="gcc-11"

PATH_ALPHA=/opt/kernel/gcc-${CV}-nolibc/alpha-linux/bin
PATH_ARM=/opt/kernel/gcc-${CV}-nolibc/arm-linux-gnueabi/bin
PATH_ARM64=/opt/kernel/gcc-${CV}-nolibc/aarch64-linux/bin
PATH_ARC=/opt/kernel/gcc-${CV}-nolibc/arc-linux/bin
PATH_ARCV2=/opt/kernel/gcc-${CV}-nolibc/arcv2-linux/bin
# ICE with gcc 9.2.0, gcc 9.3.0, gcc 10.3.0
# Assembler errors with gcc 8.4.0, 8.5.0 (v4.19.y)
# internal compiler error with gcc 11.1.0, 11.3.0, 11.4.0, 12.2.0
# PATH_C6X=/opt/kernel/gcc-${CV}-nolibc/c6x-elf/bin
PATH_C6X=/opt/kernel/gcc-8.3.0-nolibc/c6x-elf/bin
PATH_CSKY=/opt/kernel/gcc-${CV}-nolibc/csky-linux/bin
PATH_H8300=/opt/kernel/gcc-${CV}-nolibc/h8300-linux/bin
PATH_HEXAGON=/opt/kernel/hexagon/bin
# loongarch needs 13.2+ to avoid 64-bit divide operations in drm code (6.9+)
PATH_LOONGARCH=/opt/kernel/gcc-${CV13}-nolibc/loongarch64-linux-gnu/bin
PATH_M68=/opt/kernel/gcc-${CV}-nolibc/m68k-linux/bin
PATH_MICROBLAZE=/opt/kernel/gcc-${CV}-nolibc/microblaze-linux/bin
PATH_MIPS=/opt/kernel/gcc-${CV}-nolibc/mips64-linux/bin
PATH_NDS32=/opt/kernel/gcc-${CV}-nolibc/nds32le-linux/bin
PATH_NIOS2=/opt/kernel/gcc-${CV}-nolibc/nios2-linux/bin
PATH_OPENRISC=/opt/kernel/gcc-${CV}-nolibc/or1k-linux/bin
PATH_PARISC=/opt/kernel/gcc-${CV}-nolibc/hppa-linux/bin
PATH_PARISC64=/opt/kernel/gcc-${CV}-nolibc/hppa64-linux/bin
PATH_PPC=/opt/kernel/gcc-${CV}-nolibc/powerpc64-linux/bin
PATH_RISCV64=/opt/kernel/gcc-${CV}-nolibc/riscv64-linux/bin
PATH_RISCV32=/opt/kernel/gcc-${CV}-nolibc/riscv32-linux/bin
PATH_S390=/opt/kernel/gcc-${CV}-nolibc/s390-linux/bin
PATH_SH4=/opt/kernel/gcc-${CV}-nolibc/sh4-linux/bin
PATH_SPARC=/opt/kernel/gcc-${CV}-nolibc/sparc64-linux/bin
PATH_X86=/opt/kernel/gcc-${CV}-nolibc/x86_64-linux/bin
PATH_XTENSA=/opt/kernel/gcc-${CV}-nolibc/xtensa-linux/bin

if [[ ${linux_version_code} -ge $(kernel_version 6 8) ]]; then
    # Avoid drm 64-bit divide build failures seen with gcc 12.x and older
    # in v6.9+.
    PATH_CSKY=/opt/kernel/gcc-${CV13}-nolibc/csky-linux/bin
    PATH_MIPS=/opt/kernel/gcc-${CV13}-nolibc/mips64-linux/bin
    PATH_OPENRISC=/opt/kernel/gcc-${CV13}-nolibc/or1k-linux/bin
    PATH_PARISC=/opt/kernel/gcc-${CV13}-nolibc/hppa-linux/bin
    PATH_XTENSA=/opt/kernel/gcc-${CV13}-nolibc/xtensa-linux/bin
fi

PATH_LLVM=/opt/kernel/clang+llvm-16.0.4-x86_64-linux-gnu-ubuntu-22.04/bin

PREFIX_ARC="arc-elf-"
PREFIX_ARCV2="arc-elf-"
PREFIX_ARM="arm-linux-gnueabi-"
PREFIX_PPC=powerpc64-linux-
PREFIX_S390="s390-linux-"
PREFIX_X86="x86_64-linux-"

BUILDDIR="/tmp/buildbot-builddir"
LOG="/tmp/buildlog.stable-build-arch"

trap __cleanup EXIT SIGHUP SIGINT SIGQUIT SIGILL SIGTRAP SIGABRT SIGBUS SIGFPE SIGSEGV SIGALRM SIGTERM SIGPWR

rel=$(git describe --match 'v*' | cut -f1 -d- | cut -f1,2 -d.)
relx=$(echo ${rel} | sed -e 's/\.//' | sed -e 's/v//')
branch=$(git branch | cut -f2 -d' ')

# Limit file size to ~3.5 GB to prevent log file sizes from getting
# out of control while at the same time supporting large images
# (x86_64/allyesconfig: above 1GB).
ulimit -f $((3500*1024))

configcmd="olddefconfig"

if [[ ${linux_version_code} -lt $(kernel_version 5 4) ]]; then
    # Older releases don't like gcc 6+
    PATH_S390=/opt/kernel/gcc-${CV8}-nolibc/s390-linux/bin
fi

maxload=$(($(nproc) * 3 / 2))

errors=0
builds=0

ref=$(git describe --match 'v*')
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
PREFIX=""
PREFIX32=""
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
    c6x)
	cmd=(${cmd_c6x[*]})
	PREFIX="c6x-elf-"
	# PREFIX="tic6x-uclinux-"
	PATH=${PATH_C6X}:${PATH}
	;;
    csky)
	cmd=(${cmd_csky[*]})
	PREFIX="csky-linux-"
	PATH=${PATH_CSKY}:${PATH}
	;;
    h8300)
	cmd=(${cmd_h8300[*]})
	PREFIX="h8300-linux-"
	PATH=${PATH_H8300}:${PATH}
	;;
    hexagon)
	cmd=(${cmd_hexagon[*]})
	if [[ ${linux_version_code} -lt $(kernel_version 5 10) ]]; then
	    PREFIX="hexagon-linux-"
	    PATH=${PATH_HEXAGON}:${PATH}
	else
	    PREFIX="hexagon-unknown-linux-gnu-"
	    PATH=${PATH_LLVM}:${PATH}
	    CCMD="clang"
	    EXTRA_CMD="CC=clang LLVM=1 LLVM_IAS=1"
	fi
	;;
    i386)
	cmd=(${cmd_i386[*]})
	PREFIX=${PREFIX_X86}
	PATH=${PATH_X86}:${PATH}
	;;
    loongarch)
	cmd=(${cmd_loongarch[*]})
	PREFIX="loongarch64-linux-gnu-"
	PATH=${PATH_LOONGARCH}:${PATH}
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
	PREFIX="or1k-linux-"
	PATH=${PATH_OPENRISC}:${PATH}
	;;
    parisc)
	cmd=(${cmd_parisc[*]})
	PREFIX="hppa-linux-"
	PATH=${PATH_PARISC}:${PATH}
	;;
    parisc64)
	cmd=(${cmd_parisc64[*]})
	PREFIX="hppa64-linux-"
	PREFIX32="hppa-linux-"
	if [[ ${linux_version_code} -lt $(kernel_version 5 15) ]]; then
	    ARCH=parisc
	fi
	if [[ ${linux_version_code} -gt $(kernel_version 6 4) ]]; then
	    # parisc after v6.4 wants at least gcc v12.0
	    PATH_PARISC=/opt/kernel/gcc-${CV12}-nolibc/hppa-linux/bin
	    PATH_PARISC64=/opt/kernel/gcc-${CV12}-nolibc/hppa64-linux/bin
	fi
	PATH=${PATH_PARISC64}:${PATH_PARISC}:${PATH}
	;;
    powerpc)
	    PATH_PARISC64=/opt/kernel/gcc-${CV}-nolibc/hppa64-linux/bin
	cmd=(${cmd_powerpc[*]})
	PREFIX="${PREFIX_PPC}"
	PATH=${PATH_PPC}:${PATH}
	# EXTRA_CMD="KALLSYMS_EXTRA_PASS=1"
	;;
    riscv32)
	ARCH=riscv
	cmd=(${cmd_riscv32[*]})
	PREFIX="riscv32-linux-"
	PATH=${PATH_RISCV32}:${PATH}
	;;
    riscv64)
	ARCH=riscv
	cmd=(${cmd_riscv64[*]})
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
	PREFIX="${PREFIX_X86}"
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

if [[ -n "${fixup_common}" ]]; then
    fixup+=("${fixup_common}")
fi

if [[ "${CCMD}" = "clang" ]]; then
    compiler_version="$(clang --version | head -n 1)"
    assembler_version=""
else
    compiler_version="$(${PREFIX}gcc --version | head -n 1)"
    assembler_version="$(${PREFIX}gcc -Wa,--version -c -x assembler /dev/null -o /dev/null 2>/dev/null | head -n 1)"
fi

echo "Compiler version: ${compiler_version}"
if [[ -n "${assembler_version}" ]]; then
    echo "Assembler version: ${assembler_version}"
fi

echo

CROSS=""
if [ "${PREFIX}" != "" ]; then
	CROSS="CROSS_COMPILE=${PREFIX}"
fi

CROSS32=""
if [ "${PREFIX32}" != "" ]; then
	CROSS32="CROSS32_COMPILE=${PREFIX32}"
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
	    if ! make ARCH=${ARCH} O=${BUILDDIR} CC="${GCC_PERF}" defconfig >/dev/null 2>${LOG}; then
		echo "failed (config)"
		dumplog 100 "${LOG}"
		continue
	    fi
	    make ARCH=${ARCH} O=${BUILDDIR} CC="${GCC_PERF}" NO_LIBTRACEEVENT=1 NO_BPF_SKEL=1 "${cmd[$i]}" >/dev/null 2>${LOG}
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

	if ! make ${CROSS} ${CROSS32} ARCH=${ARCH} O=${BUILDDIR} ${EXTRA_CMD} ${cmd[$i]} </dev/null >${LOG} 2>&1; then
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
	    # if needed for testing
	    # cp "${BUILDDIR}/.config" "/tmp/config.${build}.$$"
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
