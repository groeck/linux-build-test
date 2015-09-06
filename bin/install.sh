if [ ! -e /tmp/$1 ]
then
	echo $1 not found
	exit 1
fi

sudo mv /tmp/$1 /opt/toolchains
sudo tar xf /opt/toolchains/$1 -C /opt/kernel
