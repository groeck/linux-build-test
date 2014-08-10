#!/bin/bash

# Script to import the -next tree into our -stable tree

echo "$(date): running"

# The current directory is the next git tree.
# Thanks buildbot, it already points to the latest version of -next.
# We have to copy it into the 'next branch of our -stable tree.

NEXT=$(pwd)

# Track local repository if not already tracked
git remote | grep local 2>/dev/null
if [ $? -ne 0 ]
then
	git remote add local ssh://git@server.roeck-us.net/var/cache/git/linux-stable.git
fi

git fetch --all
git reset --hard origin/master
git push --force local master:next
git prune
