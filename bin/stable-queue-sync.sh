#!/bin/bash

PATH=${PATH}:${HOME}/bin

echo "$(date): running"

# The current directory is the stable-queue git tree

if [ $# -gt 0 ]
then
	releases=($*)
else
	releases=(4.19 5.4 5.10 5.15 6.1 6.6 6.12 6.13)
fi

do_import()
{
	release=$1
	target=linux-${release}.y.queue
	source="origin/linux-${release}.y"
	source_s="stable/linux-${release}.y"

	echo "Importing ${release}"
	echo "source: ${source} target: ${target}"

	# Add local repository to remote only if needed
	git remote | grep -q local || {
		git remote add local git://server.roeck-us.net/git/linux-stable.git
		git config remote.local.pushurl "ssh://git@server.roeck-us.net//var/cache/git/linux-stable.git"
	}
	# Also add -stable if needed
	git remote | grep -q stable || {
	    git remote add stable git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
	}

	git fetch --all
	# Check if source branch exists. If not, there is nothing we can do.
	if ! git branch -r | grep -q "${source}" >/dev/null 2>&1; then
		if [ -z "${source_s}" ]; then
			echo "Source branch does not exist, skipping."
			return 1
		fi
		echo "Source branch does not exist in ${source}, checking ${source_s}."
		if ! git branch -r | grep -q "${source_s}" >/dev/null 2>&1; then
			echo "Source branch does not exist, skipping."
			return 1
		fi
		source=${source_s}
	fi
	# Check if target branch exists
	# If not, we have to create it first
	# Note: "git push local ${source}:${target}" does not work
	# if ${target} does not exist.
	if ! git branch -r | grep -q "local/${target}" >/dev/null 2>&1; then
		if ! git checkout -b "${target}" "${source}"; then
		    return 1
		fi
		git push local "${target}"
		return $?
	else
		if ! git push local "${source}:${target}"; then
			echo "push failed, retrying with force"
			git push --force local "${source}:${target}"
			return $?
		fi
	fi
	echo "describe source: $(git describe --match 'v*' ${source})"
	echo "describe target: $(git describe --match 'v*' local/${target})"
	return 0
}

# Auto-clean repository if needed
if [[ -e .git/gc.log ]]; then
	git prune
	rm -f .git/gc.log
fi

rv=0
for rel in ${releases[*]}
do
	do_import ${rel}
	rv=$((rv + $?))
done

echo "$(date): complete"
exit ${rv}
