progdir=$(cd $(dirname $0); pwd)

# For now this is exectly the same as the setup for beagle,
# so just execute it.

exec ${progdir}/../beagle/setup.sh $*
