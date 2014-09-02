#!/bin/bash

git remote | grep local >/dev/null 2>&1
if [ $? -ne 0 ]
then
	git remote add local git://server.roeck-us.net/git/linux.git
	if [ $? -ne 0 ]
	then
		exit 1
	fi
	git remote set-url --push local ssh://git@server.roeck-us.net/var/cache/git/linux.git
	if [ $? -ne 0 ]
	then
		exit 1
	fi
fi

git fetch --all
git push local origin/master:master

for a in $(git tag -l | grep v3 | \
	egrep -v "v3.0|v3.1\$|v3.1\.|v3.1-|v3.3|v3.5|v3.6|v3.7|v3.8|v3.9|v3.11|v3.13|v3.15")
do
	echo -n "tag:$a: "
	git push local refs/tags/$a
	if [ $? -ne 0 ]
	then
		echo "git push error (tags): aborting"
		exit 1
	fi
done

exit 0
