#!/bin/bash

PATH=${PATH}:${HOME}/bin

echo "$(date): running"

# The current directory is the stable-queue git tree

if [ $# -gt 0 ]
then
	releases=($*)
else
	releases=(3.12 3.18 4.1)
fi

do_import()
{
	release=$1
	target=linux-${release}.y.queue
	if [ "${release}" = "3.12" ]
	then
		source=origin/stable-${release}-queue
	else
		source=origin/linux-${release}.y-queue
	fi

	echo "Importing ${release}"
	echo source: ${source} target: ${target}

	# Add local repository to remote only if needed
	git remote | grep local || {
		git remote add local git://server.roeck-us.net/git/linux-stable.git
		git config remote.local.pushurl "ssh://git@server.roeck-us.net//var/cache/git/linux-stable.git"
	}
	git fetch --all
	git push local ${source}:${target}
	if [ $? -ne 0 ]
	then
		echo "push failed, retrying with force"
		git push --force local ${source}:${target}
	fi
}

for rel in ${releases[*]}
do
	do_import ${rel}
done

echo "$(date): complete"
