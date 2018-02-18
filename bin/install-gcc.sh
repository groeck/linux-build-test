if [ -e /tmp/$1 ]; then
    f=/tmp/$1
elif [ -e $1 ]; then
    f=$1
else
    echo "$1 not found"
    exit 1
fi

sudo mv $f /opt/toolchains
sudo tar xf /opt/toolchains/$(basename $f) -C /opt/kernel
