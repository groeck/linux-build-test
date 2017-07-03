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
    if [ $? -ne 0 ]
    then
        exit 1
    fi
    make -j20 install
    if [ $? -ne 0 ]
    then
        exit 1
    fi
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
    if [ $? -ne 0 ]
    then
        exit 1
    fi
    make -j20 install
    if [ $? -ne 0 ]
    then
        exit 1
    fi
fi

if [ -z "$1" -o "$1" = "v2.5" ]
then
    git clean -d -x -f -q
    git checkout v2.5.1-local
    ./configure --prefix=/opt/buildbot/qemu-install/v2.5 \
	--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough \
	--target-list="ppc64-softmmu"
    if [ $? -ne 0 ]
    then
        exit 1
    fi
    make -j20 install
    if [ $? -ne 0 ]
    then
        exit 1
    fi
fi

if [ -z "$1" -o "$1" = "v2.6" ]
then
    git clean -d -x -f -q
    git checkout v2.6.2-local
    ./configure --prefix=/opt/buildbot/qemu-install/v2.6 \
	--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough \
	--target-list="ppc64-softmmu arm-softmmu sparc64-softmmu"
    if [ $? -ne 0 ]
    then
        exit 1
    fi
    make -j20 install
    if [ $? -ne 0 ]
    then
        exit 1
    fi
fi

if [ -z "$1" -o "$1" = "v2.7" ]
then
    git clean -d -x -f -q
    git checkout v2.7.0-local
    ./configure --prefix=/opt/buildbot/qemu-install/v2.7 \
	--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough
    if [ $? -ne 0 ]
    then
        exit 1
    fi
    make -j20 install
    if [ $? -ne 0 ]
    then
        exit 1
    fi
fi

if [ -z "$1" -o "$1" = "v2.8" ]
then
    dobuild v2.8.1-local v2.8 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough"
    if [ $? -ne 0 ]
    then
        exit 1
    fi
fi

if [ -z "$1" -o "$1" = "v2.9" ]
then
    dobuild v2.9.0-local v2.9 \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough"
    if [ $? -ne 0 ]
    then
        exit 1
    fi
fi

if [ "$1" = "master" ]
then
    dobuild master-local master \
	"--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough"
	"nios2-softmmu sparc64-softmmu sparc-softmmu"
    if [ $? -ne 0 ]
    then
        exit 1
    fi
fi
