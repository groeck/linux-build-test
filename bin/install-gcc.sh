if [ -z "$1" ]; then
    echo "Need parameter"
    exit 1
fi

if [ ! -f /tmp/$1 ]; then
    f=/tmp/$1
elif [ -f $1 ]; then
    f=$1
else
    echo "$1 does not exist or is not a file"
    exit 1
fi

sudo mv $f /opt/toolchains
sudo tar xf /opt/toolchains/$(basename $f) -C /opt/kernel
