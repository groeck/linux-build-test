#!/bin/bash

PATH=${PATH}:${HOME}/bin

echo "$(date): running"

# The current directory is the stable-queue git tree

if [ $# -gt 0 ]
then
	releases=($*)
else
	releases=(3.18 4.4 4.9 4.11)
fi

do_import()
{
	release=$1
	target=linux-${release}.y.queue
	case "${release}" in
	"3.12")
		source=origin/stable-${release}-queue
		;;
	"3.10" | "4.1")
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
	# Also add -stable if needed
	# git remote | grep stable || {
	# 	git remote add stable git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
	# }

	git fetch --all
	# Check if source branch exists. If not, there is nothing we can do.
	git branch -r | grep ${source}  >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
		echo "Source branch does not exist: Aborting."
		return 1
	fi
	# Check if target branch exists
	# If not, we have to create it first
	# Note: "git push local ${source}:${target}" does not work
	# if ${target} does not exist.
	git branch -r | grep local/${target} >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
		git checkout -b ${target} ${source}
		if [ $? -ne 0 ]
		then
		    return 1
		fi
		git push local ${target}
		return $?
	else
		git push local ${source}:${target}
		if [ $? -ne 0 ]
		then
			echo "push failed, retrying with force"
			git push --force local ${source}:${target}
			return $?
		fi
	fi
	return 0
}

rv=0
for rel in ${releases[*]}
do
	do_import ${rel}
	rv=$((${rv} + $?))
done

echo "$(date): complete"
exit ${rv}
