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
		# Skip 3.16.y failures
		if [ "$a" = "linux-3.16.y" ]
		then
			echo "Skipping $a"
			continue
		fi
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

epoch=$(date +%s)
mepoch=$((${epoch} - 2500000))  # ~ one month back

git tag -l | while read a
do
	tepoch=$(git log -1 --format=%ct $a)
	if [ -n "${tepoch}" ]
	then
		if [ ${tepoch} -gt ${mepoch} ]
		then
			echo -n "tag:$a: "
			git push local refs/tags/$a
		fi
	fi
done

exit 0
