#!/bin/sh

if [ -z "$1" -o ! -d "$1" ]
then
	echo "bad command line (missing directory) : aborting"
	exit 1
fi

cd $1

git fetch --all

git branch -r | grep upstream | grep -v linux-2.6 | cut -f2 -d'/' | while read a
do
	echo -n "$a: "
	git push origin upstream/$a:$a
	if [ $? -ne 0 ]
	then
		echo "git push error: aborting"
		exit 1
	fi
done

git tag -l | grep v3 | \
	egrep -v "v3.1\$|v3.1\.|v3.1-|v3.3|v3.5|v3.6|v3.9|v3.8|v3.7|v3.2" | while read a
do
	echo -n "tag:$a: "
	git push origin refs/tags/$a
done
