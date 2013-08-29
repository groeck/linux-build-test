#!/bin/bash

WARN=/tmp/warnings.$$
MAIL_FILE=/tmp/mail.$$
ERR=/tmp/error.$$

BRANCH=$(git branch | egrep "^\*" | cut -f2 -d' ')

REPOSITORY=/home/groeck/src/linux-staging

PATH_MIPS=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/mips32-poky-linux
PATH_PPC=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin/ppc64e5500-poky-linux
PATH_ARM=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/armv5te-poky-linux-gnueabi
PATH_X86=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/x86_64-poky-linux
PATH_M68K=/opt/kernel/gcc-4.6.3-nolibc/m68k-linux/bin

export PATH=${PATH_MIPS}:${PATH_PPC}:${PATH_ARM}:${PATH_X86}:${PATH_M68K}:${PATH}

errors=0
builds=0
retcode=0

cmd_i386=(defconfig allyesconfig allmodconfig)
cmd_x86_64=(defconfig allyesconfig allmodconfig)
cmd_mips=(defconfig allmodconfig cavium_octeon_defconfig)
cmd_arm=(defconfig allmodconfig multi_v7_defconfig)
cmd_powerpc=(defconfig allmodconfig)
cmd_m68k=(defconfig allmodconfig)

send_mail()
{
	echo "From Guenter Roeck <linux@roeck-us.net>" > ${MAIL_FILE}
	echo "Subject: $1" >> ${MAIL_FILE}
	echo "MIME-Version: 1.0" >> ${MAIL_FILE}
	echo "Content-Transfer-Encoding: 8bit" >> ${MAIL_FILE}
	echo "Content-Type: text/plain; charset=utf-8" >> ${MAIL_FILE}
	echo >> ${MAIL_FILE}
	cat $2 >> ${MAIL_FILE}
	git send-email --quiet --to=linux@roeck-us.net \
		    --suppress-cc=all --confirm=never --no-chain-reply-to \
		    ${MAIL_FILE} >/dev/null 2>/dev/null
	rm -f ${MAIL_FILE}
}

do_smatch_check()
{
    # Run smatch only on compiled files in drivers/hwmon.
    # This doesn't get us all of them, but we avoid false positives
    # due to uncompilable files.
    #
    local l=$(ls drivers/hwmon/*.o | grep -v built-in.o | egrep -v 'mod.o$' 2>/dev/null)
    local x

    for x in $l
    do
        srcfile=$(echo $x | sed -e 's/\.o/.c/')
	echo "smatch: checking $x [${srcfile}]"
	/opt/buildbot/smatch/smatch_scripts/kchecker --spammy ${srcfile}
    done
}

doit()
{
    local ARCH=$1
    local i

    # We should be on the target directory, in the target branch

    local OPTIONS=""
    local SMATCH=0

    case ${ARCH} in
    x86_64)
	cmd=(${cmd_x86_64[*]})
	PREFIX="x86_64-poky-linux-"
	OPTIONS="W=1 C=1"
	SMATCH=1
	;;
    i386) cmd=(${cmd_i386[*]}); PREFIX="x86_64-poky-linux-";;
    mips) cmd=(${cmd_mips[*]}); PREFIX="mips-poky-linux-";;
    powerpc) cmd=(${cmd_powerpc[*]}); PREFIX="powerpc64-poky-linux-";;
    arm) cmd=(${cmd_arm[*]}); PREFIX="arm-poky-linux-gnueabi-";;
    m68k) cmd=(${cmd_m68k[*]}); PREFIX="m68k-linux-";;
    esac

    if [ "${PREFIX}" != "" ]; then
	CROSS="CROSS_COMPILE=${PREFIX}"
    fi

    i=0
    while [ $i -lt ${#cmd[*]} ]
    do
	failed=0
    	echo "$(basename $0): build:${cmd[$i]} branch:${BRANCH} arch:${ARCH} prefix:${PREFIX}"
	git clean -x -d -f -q
	make ${CROSS} ARCH=${ARCH} ${cmd[$i]} >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
		echo failed to configure build for ${ARCH}:${cmd[$i]}
	 	i=$(expr $i + 1)
	 	continue
	fi
	make ${CROSS} ARCH=${ARCH} oldnoconfig >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
		echo failed to run oldnoconfig for ${ARCH}:${cmd[$i]}
	 	i=$(expr $i + 1)
	 	continue
	fi
	ext=$(basename $(pwd)).${BRANCH}.${ARCH}.$i
    	builds=$(expr ${builds} + 1)
	make ${CROSS} -j10 -i ARCH=${ARCH} >/dev/null 2> >(tee ${ERR} >&2)
	#
	# If options are set, repeat the exercise for all object files
	# in drivers/hwmon. This reduces build time and number of warnings
	# we have to deal with.
	# The odd redirect is to get error output to the console (for the
	# buildbot log) and into a file for the status email.
	#
	if [ -n "${OPTIONS}" ]
	then
	    for f in $(ls drivers/hwmon/*.o | grep -v built-in.o | egrep -v 'mod.o$' 2>/dev/null)
	    do
	    	rm -f $f
	        make ${CROSS} -j10 -i ${OPTIONS} ARCH=${ARCH} $f >/dev/null 2> >(tee ${ERR}.tmp >&2)
		cat ${ERR}.tmp >> ${ERR}
		rm -f ${ERR}.tmp
	    done
	fi
	# If smatch build is asked for as well, do another run with smatch.
	# Append smatch output to warning log.
	rm -f ${WARN}.smatch
	if [ ${SMATCH} -ne 0 ]
	then
		do_smatch_check > /dev/null 2> >(tee ${WARN}.smatch >&2)
	else
		touch ${WARN}.smatch
	fi
	grep Error ${ERR} >/dev/null 2>/dev/null
	if [ $? -eq 0 ]; then
    	    errors=$(expr ${errors} + 1)
    	    echo "$(basename $0): build:${cmd[$i]} branch:${BRANCH} arch:${ARCH} prefix:${PREFIX} failed"
	    failed=1
	fi
	egrep "drivers/hwmon" ${ERR} | \
		egrep -v "drivers/hwmon/*\.ko\] undefined" | \
		egrep -v "drivers/hwmon/*\.ko\] has no CRC" | \
		egrep -v "drivers/hwmon.*mod\.[co]: undefined" | \
		egrep -v "drivers/hwmon.*mod\.[co]: No such" | \
		egrep -v "\[.*hwmon.*mod\.o\] Error 1" | \
		egrep -v "\[.*hwmon.*\.ko\] Error 1" \
		> ${WARN}.tmp 2>&1
	if [ -s ${WARN}.tmp -o -s ${WARN}.smatch ]; then
	    if [ -s ${WARN} ]; then
		echo "--------------------" >> ${WARN}
	    fi
	    echo "Build: ${BRANCH}:${ARCH}:${cmd[$i]}" >> ${WARN}
	    echo >> ${WARN}
	    cat ${WARN}.tmp >> ${WARN}
	    if [ -s ${WARN}.smatch ]
	    then
	    	[ -s ${WARN}.tmp ] && echo "--------------------" >> ${WARN}
		echo "smatch log:" >> ${WARN}
	        cat ${WARN}.smatch >> ${WARN}
	    fi
	    if [ ${failed} -gt 0 ]
	    then
		echo "Build: ${BRANCH}:${ARCH}:${cmd[$i]} failed with hwmon warnings/errors"
	    	retcode=1
	    fi
	fi
	rm -f ${WARN}.tmp ${ERR}
	i=$(expr $i + 1)
    done
    return 0
}

for build in x86_64 i386 mips powerpc arm m68k
do
	doit ${build}
done

git clean -d -x -f -q

echo >> ${WARN}
echo "-----------------------" >> ${WARN}
echo "Total builds: ${builds} Total build errors: ${errors}" >> ${WARN}

send_mail "${BRANCH} build warnings and errors" ${WARN}

rm -f ${WARN} ${WARN}.smatch ${ERR}

exit ${retcode}
