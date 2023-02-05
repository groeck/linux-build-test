#!/bin/bash

# This makes sure that all CPUs are busy without overloading the system
# too much.
parallel=$(($(nproc) * 3 / 2))

checkexit()
{
	if [ $1 -ne 0 ]; then
		exit $1
	fi
}

rinse()
{
	git clean -d -x -f -q
	git submodule foreach --recursive git clean -d -x -f -q
	git reset --hard
	git submodule foreach --recursive git reset --hard
	# slirp doesn't always exist as submodule.
	# If it does, it creates havoc if one tries to check out
	# an older branch.
	git submodule deinit slirp 2>/dev/null
}

dobuild()
{
	local branch=$1
	local installdir=$2
	local options=$3
	local targets=$4
	local prefix="/opt/buildbot/qemu-install/${installdir}"
	local rv

	echo branch: ${branch}
	echo installdir: ${installdir}
	echo options: ${options}

	# Clean up as good as we can prior to checking out a different branch
	rinse

	if ! git checkout ${branch}; then
	    echo "Unable to check out ${branch}"
	    return 1
	fi
	if [ -z "${targets}" ]; then
	    if ! ./configure --prefix=${prefix} ${options}; then
		return 1
	    fi
	else
	    echo targets: ${targets}
	    if ! ./configure --prefix=${prefix} ${options} --target-list="${targets}"; then
		return 1
	    fi
	fi
	if ! make -j${parallel} install; then
	    return 1
	fi
	return 0
}

if [ ! -d .git -o ! -f qemu-io.c ]
then
	if [ ! -d qemu ]; then
		echo "Bad directory"
		exit 1
	fi
	cd qemu
fi

dobuild_common()
{
    dobuild $1 $2 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-hax \
	--disable-xen --disable-xen-pci-passthrough \
	--disable-libssh $3"
    checkexit $?
}

if [ -z "$1" -o "$1" = "v4.2" ]; then
    dobuild_common v4.2.1-local v4.2 "--disable-vnc-png"
    if [ -n "$2" ]; then
	shift
    fi
fi

if [ -z "$1" -o "$1" = "v6.2" ]; then
    dobuild_common v6.2.0-local v6.2 "--disable-vnc-png"
    if [ -n "$2" ]; then
	shift
    fi
fi

if [ -z "$1" -o "$1" = "v7.0" ]; then
    dobuild_common v7.0.0-local v7.0 "--disable-vnc-png"
    if [ -n "$2" ]; then
	shift
    fi
fi

if [ -z "$1" -o "$1" = "v7.1" ]; then
    dobuild_common v7.1.0-local v7.1 "--disable-png"
    if [ -n "$2" ]; then
	shift
    fi
fi

if [ -z "$1" -o "$1" = "v7.2" ]; then
    dobuild_common v7.2.0-local v7.2 "--disable-png --disable-strip --extra-cflags=-g"
#    dobuild_common v7.2.0-local v7.2-debug \
#	"--disable-vnc-png --enable-debug --disable-strip --extra-cflags=-g"
    if [ -n "$2" ]; then
	shift
    fi
fi

if [ -z "$1" -o "$1" = "master" ]; then
    dobuild_common master-local master "--disable-png --disable-strip"
    # While it would be desirable to have debugging enabled in general,
    # it slows down the system too much. Generate separate master-debug
    # specifically for to have images with debugging enabled available
    # if needed.
    dobuild_common master-local master-debug \
	"--disable-png --enable-debug --disable-strip --extra-cflags=-g"
fi
