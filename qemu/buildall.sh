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

	# Some odd changes between releases require this directory to be
	# clean/removed.
	# If it isn't, changing the branch may fail.
	rm -rf slirp
	# Clean up as much as we can. Yes, that will remove any uncommitted
	# changes, but it is necessary to be able to switch between branches.
	git reset --hard HEAD >/dev/null 2>&1
	git clean -d -x -f -q >/dev/null 2>&1
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

if [ -z "$1" -o "$1" = "meta" ]
then
    git clean -d -x -f -q
    git checkout meta-v1.3.1
    ./configure --prefix=/opt/buildbot/qemu-install/metag \
	--disable-user --disable-xen --disable-xen-pci-passthrough \
	--disable-vnc-tls --disable-werror --disable-docs \
	--disable-vnc-png \
	--target-list=meta-softmmu
    checkexit $?
    make -j${parallel} install
    checkexit $?
fi

if [ -z "$1" -o "$1" = "linaro" ]
then
    git clean -d -x -f -q
    git checkout v2.3.50-local-linaro
    ./configure --prefix=/opt/buildbot/qemu-install/v2.3.50-linaro \
	--disable-user --disable-xen --disable-xen-pci-passthrough \
	--disable-vnc-tls --disable-vnc-ws --disable-quorum \
	--disable-vnc-png --with-gtkabi=3.0 \
	--disable-docs --disable-werror \
	--disable-curl \
	--target-list=arm-softmmu
    checkexit $?
    make -j${parallel} install
    checkexit $?
fi

if [ -z "$1" -o "$1" = "csky" ]
then
    dobuild v2.8.1-local-csky csky \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-vnc-png \
	--with-gtkabi=3.0 \
	--disable-werror \
	--target-list=cskyv2-softmmu \
	--disable-xen --disable-xen-pci-passthrough"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "v2.8" ]
then
    dobuild v2.8.1-local v2.8 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-vnc-png \
	--with-gtkabi=3.0 \
	--disable-werror \
	--disable-xen --disable-xen-pci-passthrough"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "v2.9" ]
then
    dobuild v2.9.1-local v2.9 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-vnc-png \
	--with-gtkabi=3.0 \
	--disable-xen --disable-xen-pci-passthrough"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "v2.10" ]
then
    dobuild v2.10.2-local v2.10 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "v2.11" ]
then
    dobuild v2.11.2-local v2.11 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-vnc-png \
	--with-gtkabi=3.0 \
	--disable-xen --disable-xen-pci-passthrough"
    checkexit $?
    dobuild v2.11.0-q800 v2.11-m68k \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-vnc-png \
	--disable-xen --disable-xen-pci-passthrough \
	--with-gtkabi=3.0 \
	--target-list=m68k-softmmu"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "v2.12" ]
then
    dobuild v2.12.1-local v2.12 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-vnc-png \
	--with-gtkabi=3.0 \
	--disable-xen --disable-xen-pci-passthrough"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "v3.0" ]
then
    dobuild v3.0.1-local v3.0 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-vnc-png \
	--with-gtkabi=3.0 \
	--disable-xen --disable-xen-pci-passthrough"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "v3.1" ]
then
    dobuild v3.1.0-local v3.1 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-vnc-png \
	--disable-xen --disable-xen-pci-passthrough"
    checkexit $?
    dobuild v3.1.0-q800 v3.1-m68k \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-vnc-png \
	--disable-xen --disable-xen-pci-passthrough \
	--target-list=m68k-softmmu"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "v4.0" ]; then
    dobuild v4.0.0-local v4.0 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-vnc-png \
	--disable-xen --disable-xen-pci-passthrough \
	--disable-strip --extra-cflags=-g"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "v4.0-q800" ]; then
    dobuild v4.0.0-q800 v4.0-m68k \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-vnc-png \
	--disable-xen --disable-xen-pci-passthrough \
	--disable-strip --extra-cflags=-g \
	--target-list=m68k-softmmu"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "v4.1" ]; then
    dobuild v4.1.0-local v4.1 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-vnc-png \
	--disable-xen --disable-xen-pci-passthrough \
	--disable-strip --extra-cflags=-g"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "master" ]; then
    dobuild master-local master \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt --disable-vnc-png \
	--disable-xen --disable-xen-pci-passthrough \
	--enable-debug --disable-strip --extra-cflags=-g"
    checkexit $?
fi
