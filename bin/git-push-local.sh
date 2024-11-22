#!/bin/bash

git remote | grep local >/dev/null 2>&1
if [ $? -ne 0 ]
then
	if ! git remote add local git://server.roeck-us.net/git/linux-stable.git; then
		exit 1
	fi
	if ! git remote set-url --push local ssh://git@server.roeck-us.net/var/cache/git/linux-stable.git; then
		exit 1
	fi
fi

git fetch --all

epoch="$(date +%s)"
mepoch="$((epoch - 2500000))"  # ~ one month back

for a in $(git branch -r | grep "origin/linux-[4-9]" | cut -f2 -d'/'); do
	lepoch="$(git log -1 --format=%ct origin/$a)"
	if [[ -z "${lepoch}" ]] || [[ "${lepoch}" -lt "${mepoch}" ]]; then
		continue
	fi
	echo -n "$a: "
	if ! git push local origin/$a:$a; then
		# Try again. Create local branch, then push it.
		# If that doesn't work, give up.
		echo Trying to clone new upstream branch $a
		git branch -D $a >/dev/null 2>&1
		if ! git checkout -b $a origin/$a; then
			echo "git checkout error (branches): aborting"
			exit 1
		fi
		if ! git push local $a; then
			echo "git push error (branches): aborting"
			exit 1
		fi
		git checkout master
		git branch -D $a
	fi
done

tags="$(git tag -l)"
for tag in ${tags}; do
	tepoch="$(git log -1 --format=%ct ${tag})"
	if [[ -n "${tepoch}" ]]; then
		if [[ "${tepoch}" -gt "${mepoch}" ]]; then
			echo -n "tag:${tag}: "
			git push local "refs/tags/${tag}"
		fi
	fi
done

exit 0
