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
git pull

echo "Remotes:"
git remote -v
echo "Reference: $(git describe)"

git push local master

echo "Updated reference: $(git describe local/master)"

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
