#!/bin/bash

echo $0

GITCACHE=/opt/buildbot/cache
command=$1
repository=$2
branch=$3

repodir=$(basename ${repository})
repodir=${repodir%.git}

ref=""
if [[ "${command}" = "start" ]]; then
    mkdir -p "${GITCACHE}"
    cd "${GITCACHE}"
    if [[ ! -d "${repodir}" ]]; then
	git clone "${repository}"
    fi
    cd ${repodir}
    git fetch origin ${branch}
    ref="$(git describe FETCH_HEAD)"
fi

echo "$(date): $* ${ref:+ref: ${ref}}" >>/tmp/buildcounter.log
