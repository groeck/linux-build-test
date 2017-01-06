if [ ! -d .git -o ! -f qemu-io.c ]
then
	if [ ! -d qemu ]
	then
		echo "Bad directory"
		exit 1
	fi
	cd qemu
fi

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

git clean -d -x -f -q
git checkout v2.8.0-local
./configure --prefix=/opt/buildbot/qemu-install/v2.8 \
	--disable-user --disable-gnutls --disable-docs \
	--disable-nettle --disable-gcrypt \
	--disable-xen --disable-xen-pci-passthrough
if [ $? -ne 0 ]
then
    exit 1
fi
make -j20 install

# git clean -d -x -f -q
# git checkout master-local
# ./configure --prefix=/opt/buildbot/qemu-install/master \
# 	--disable-user --disable-gnutls --disable-docs \
# 	--disable-nettle --disable-gcrypt \
# 	--disable-xen --disable-xen-pci-passthrough \
# 	--target-list="nios2-softmmu"
# if [ $? -ne 0 ]
# then
#     exit 1
# fi
# make -j20 install
