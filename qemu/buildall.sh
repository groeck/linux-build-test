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

	git clean -d -x -f -q
	git checkout ${branch}
	if [ -z "${targets}" ]
	then
	    ./configure --prefix=${prefix} ${options}
	else
	    echo targets: ${targets}
	    ./configure --prefix=${prefix} ${options} --target-list="${targets}"
	fi
	rv=$?
	if [ ${rv} -ne 0 ]
	then
		return ${rv}
	fi
	make -j20 install
	return $?
}

if [ ! -d .git -o ! -f qemu-io.c ]
then
	if [ ! -d qemu ]
	then
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
	--target-list=meta-softmmu
    checkexit $?
    make -j20 install
    checkexit $?
fi

if [ -z "$1" -o "$1" = "linaro" ]
then
    git clean -d -x -f -q
    git checkout v2.3.50-local-linaro
    ./configure --prefix=/opt/buildbot/qemu-install/v2.3.50-linaro \
	--disable-user --disable-xen --disable-xen-pci-passthrough \
	--disable-vnc-tls --disable-vnc-ws --disable-quorum \
	--disable-docs --disable-werror \
	--target-list=arm-softmmu
    checkexit $?
    make -j20 install
    checkexit $?
fi

if [ -z "$1" -o "$1" = "v2.8" ]
then
    dobuild v2.8.1-local v2.8 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "v2.9" ]
then
    dobuild v2.9.1-local v2.9 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
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
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough"
    checkexit $?
    dobuild v2.11.0-q800 v2.11-m68k \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough \
	--target-list=m68k-softmmu"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "v2.12" ]
then
    dobuild v2.12.0-local v2.12 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "an385" ]
then
    dobuild master-local-an385 master-an385 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough \
	--target-list=arm-softmmu"
    checkexit $?
fi

if [ -z "$1" -o "$1" = "riscv" ]
then
    dobuild v3.0.0-local-riscv v3.0-riscv \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough \
	--target-list=riscv64-softmmu"
    checkexit $?
fi

if [ "$1" = "master" ]; then
    dobuild master-local master \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough \
	--enable-debug --disable-strip"
    checkexit $?
fi
