#!/bin/bash

WARN=/tmp/warnings.$$
MAIL_FILE=/tmp/mail.$$
ERR=/tmp/error.$$

BRANCH=$(git branch | egrep "^\*" | cut -f2 -d' ')

PATH_X86=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/x86_64-poky-linux

export PATH=${PATH_X86}:${PATH}

errors=0
builds=0
retcode=0

maxload=$(($(nproc) + 4))

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

doit()
{
    local ARCH=$1
    local i
    local files

    # We should be on the target directory, in the target branch

    local OPTIONS=""
    local SMATCH=0

    PREFIX="x86_64-poky-linux-"

    case ${ARCH} in
    x86_64)
	OPTIONS="W=1 C=1"
	SMATCH=1
	;;
    esac

    if [ "${PREFIX}" != "" ]; then
	CROSS="CROSS_COMPILE=${PREFIX}"
    fi

    i=0
    while [ $i -lt 2 ]
    do
	failed=0
	echo "$(basename $0): build:$i branch:${BRANCH} arch:${ARCH} prefix:${PREFIX}"
	git clean -x -d -f -q
	make ${CROSS} ARCH=${ARCH} defconfig >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
		echo failed to run defconfig for ${ARCH}:$i
	 	i=$(expr $i + 1)
	 	continue
	fi
	# Fix up configuration file.
	# First run, build as modules. Second run, build into kernel.
	if [ $i -eq 0 ]
	then
	    sed -i 's/^# \(CONFIG_SENSORS_\)\([A-Za-z0-9_]*\).*/\1\2=m/g' .config
	else
	    sed -i 's/^# \(CONFIG_SENSORS_\)\([A-Za-z0-9_]*\).*/\1\2=y/g' .config
	fi
	make ${CROSS} ARCH=${ARCH} oldnoconfig >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
		echo failed to run oldnoconfig for ${ARCH}:$i
	 	i=$(expr $i + 1)
	 	continue
	fi
	builds=$(expr ${builds} + 1)
	make ${CROSS} -j${maxload} -i ARCH=${ARCH} >/dev/null 2> >(tee ${ERR} >&2)
	failed=$?
	#
	# If options are set, repeat the exercise for all object files
	# in drivers/hwmon and drivers/watchdog. Only do it for the
	# module build; this should catch most buildable sources.
	# This reduces build time and limits the number of repetitive warnings
	# we have to deal with.
	# The odd redirect is to get error output to the console (for the
	# buildbot log) and into a file for the status email.
	#
	rm -f ${WARN}.sparse
	touch ${WARN}.sparse
	rm -f ${WARN}.smatch
	touch ${WARN}.smatch
	if [ -n "${OPTIONS}" -a $i -eq 0 ]
	then
	    files=$(find drivers/hwmon drivers/watchdog -name '*.o' |
			grep -v built-in.o | egrep -v 'mod.o$' |
			grep -v watchdog.o 2>/dev/null)
	    rm -f ${files}
	    make ${CROSS} -j${maxload} -i ${OPTIONS} ARCH=${ARCH} ${files} >/dev/null 2> >(tee ${ERR}.tmp >&2)
	    egrep '^drivers/(hwmon|watchdog)' ${ERR}.tmp > ${WARN}.sparse 2>&1
	    rm -f ${ERR}.tmp
	    # If smatch build is asked for as well, do another run with smatch.
	    # Append smatch log messages to warning log.
	    # Run smatch on all sources, and ignore errors from the build step.
	    if [ ${SMATCH} -ne 0 ]
	    then
		sfiles=$(find drivers/hwmon drivers/watchdog -name '*.c' |
			grep -v built-in.c |
			egrep -v '.mod.c$' | sed -e 's/\.c/.o/')
		rm -f ${sfiles}
		make C=1 -j${maxload} -i \
		    CHECK="/opt/buildbot/bin/smatch --project=kernel" \
		    ${sfiles} 2>/dev/null | tee ${WARN}.smatch.tmp
		egrep '(warn|error|info):' ${WARN}.smatch.tmp | \
				egrep -v "atomic\.h:.*ignoring unreachable code" | \
				egrep -v "bitops\.h:.*ignoring unreachable code" \
				>> ${WARN}.smatch
		rm -f ${WARN}.smatch.tmp
	    fi
	fi
	if [ ${failed} -ne 0 ]; then
	    errors=$(expr ${errors} + 1)
	    echo "$(basename $0): build:$i branch:${BRANCH} arch:${ARCH} prefix:${PREFIX} failed"
	fi
	# egrep "drivers/{hwmon|watchdog}" ${ERR} > ${WARN}.tmp 2>&1
	if [ ${failed} -ne 0 -o -s ${WARN}.smatch -o -s ${WARN}.sparse ]; then
	    [ -s ${WARN} ] && {
		echo "--------------------" >> ${WARN}
	    }
	    echo "Build: ${BRANCH}:${ARCH}:$i" >> ${WARN}
	    echo >> ${WARN}
	    [ ${failed} -ne 0 ] && {
		cat ${ERR} >> ${WARN}
		echo "--------------------" >> ${WARN}
	    }
	    [ -s ${WARN}.sparse ] && {
		echo "sparse log:" >> ${WARN}
	        cat ${WARN}.sparse >> ${WARN}
		echo "--------------------" >> ${WARN}
	    }
	    [ -s ${WARN}.smatch ] && {
		echo "smatch log:" >> ${WARN}
	        cat ${WARN}.smatch >> ${WARN}
	    }
	    [ ${failed} -ne 0 ] && {
		echo "Build: ${BRANCH}:${ARCH}:$i failed with build errors"
		retcode=1
	    }
	fi
	rm -f ${WARN}.tmp ${ERR} ${WARN}.smatch
	i=$(expr $i + 1)
    done
    return 0
}

for build in x86_64 i386
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
