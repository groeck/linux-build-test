#!/bin/bash

git remote | grep local >/dev/null 2>&1
if [ $? -ne 0 ]
then
	git remote add local git://server.roeck-us.net/git/linux-stable.git
	if [ $? -ne 0 ]
	then
		exit 1
	fi
	git remote set-url --push local ssh://git@server.roeck-us.net/var/cache/git/linux-stable.git
	if [ $? -ne 0 ]
	then
		exit 1
	fi
fi

git fetch --all

for a in $(git branch -r | grep origin | grep -v HEAD | grep -v linux-2.6 | cut -f2 -d'/')
do
	echo -n "$a: "
	git push local origin/$a:$a
	if [ $? -ne 0 ]
	then
		# Try again. Create local branch, then push it.
		# If that doesn't work, give up.
		echo Trying to clone new upstream branch $a
		git branch -D $a >/dev/null 2>&1
		git checkout -b $a origin/$a
		if [ $? -ne 0 ]
		then
			echo "git checkout error (branches): aborting"
			exit 1
		fi
		git push local $a
		if [ $? -ne 0 ]
		then
			echo "git push error (branches): aborting"
			exit 1
		fi
		git checkout master
		git branch -D $a
	fi
done

for a in $(git tag -l | grep v3 | egrep -v "v3.1\$|v3.1\.|v3.1-|v3.3|v3.5|v3.6|v3.9|v3.8|v3.7")
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
