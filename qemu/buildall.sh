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

clear_submodule()
{
    local sdir=".git/modules/$1"
    local force=0

    # If the submodule is initialized, check if its remote location has changed.
    # If so, remove the local cache as well to enfore the new location.
    # Do this only conditionally because otherwise we have to keep cloning
    # the submodule for each build.
    if [[ -d "${sdir}" && -d "$2" ]]; then
	remote1="$(git -C "${sdir}" remote get-url origin)"
	remote2="$(git -C "$1" remote get-url origin)"
	if [[ "${remote1}" != "${remote2}" ]]; then
	    force=1
	fi
    fi
    git submodule deinit -f "$1" 2>/dev/null
    if [[ "${force}" -ne 0 ]]; then
	rm -rf "${sdir}"
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
	clear_submodule slirp
	# Location of other submodules may have changed.
	# Make sure they are all reinitialized.
	clear_submodule tests/fp/berkeley-softfloat-3
	clear_submodule tests/fp/berkeley-testfloat-3
	clear_submodule ui/keycodemapdb
	clear_submodule meson
	# git submodule deinit -f dtc 2>/dev/null
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
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough \
	--disable-libssh --disable-png $3"
    checkexit $?
}

build_one()
{
    case "$1" in
    "v7.2")
	dobuild_common v7.2.13-local v7.2 "--disable-hax"
	;;
    "v8.0")
	dobuild_common v8.0.5-local v8.0 "--disable-hax"
	;;
    "v8.1")
	dobuild_common v8.1.5-local v8.1 "--disable-hax"
	;;
    "v8.2")
	dobuild_common v8.2.7-local v8.2 ""
	;;
    "v9.0")
	dobuild_common v9.0.3-local v9.0 ""
	;;
    "v9.1")
	dobuild_common v9.1.0-local v9.1 "--disable-strip --extra-cflags=-g"
	# dobuild_common v9.1.0-local v9.1-debug \
	#	"--enable-debug --disable-strip --extra-cflags=-g"
	;;
    "master")
	dobuild_common master-local master "--disable-strip --extra-cflags=-g"
	;;
    "master-debug")
	# While it would be desirable to have debugging enabled in general,
	# it slows down the system too much. Generate separate master-debug
	# to have images with debugging enabled available if needed.
	dobuild_common master-local master-debug \
		"--enable-debug --disable-strip --extra-cflags=-g"
	;;
    *)
	echo "$0: unknown release: $1"
	exit 1
	;;
    esac
}

if [[ -z "$*" ]]; then
    builds="v7.2 v8.0 v8.1 v8.2 v9.0 v9.1 master master-debug"
else
    builds="$*"
fi

for build in ${builds}; do
    build_one "${build}"
done
