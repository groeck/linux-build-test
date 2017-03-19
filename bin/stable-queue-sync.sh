#!/bin/bash

PATH=${PATH}:${HOME}/bin

echo "$(date): running"

# The current directory is the stable-queue git tree

if [ $# -gt 0 ]
then
	releases=($*)
else
	releases=(4.4 4.9 4.10)
fi

do_import()
{
	release=$1
	target=linux-${release}.y.queue
	case "${release}" in
	"3.12")
		source=origin/stable-${release}-queue
		;;
	"3.10" | "3.18" | "4.1")
		source=origin/linux-${release}.y-queue
		;;
	*)
		source=origin/linux-${release}.y
		;;
	esac

	echo "Importing ${release}"
	echo source: ${source} target: ${target}

	# Add local repository to remote only if needed
	git remote | grep local || {
		git remote add local git://server.roeck-us.net/git/linux-stable.git
		git config remote.local.pushurl "ssh://git@server.roeck-us.net//var/cache/git/linux-stable.git"
	}
	git fetch --all
	# Check if target branch exists
	# If not, we have to create it first
	# Note: "git push local ${source}:${target}" does not work
	# if ${target} does not exist.
	git branch -r | grep local/${target} >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
		git checkout -b ${target} ${source}
		git push local ${target}
	else
		git push local ${source}:${target}
		if [ $? -ne 0 ]
		then
			echo "push failed, retrying with force"
			git push --force local ${source}:${target}
		fi
	fi
}

for rel in ${releases[*]}
do
	do_import ${rel}
done

echo "$(date): complete"
