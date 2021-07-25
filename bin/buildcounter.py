#!/usr/bin/env python3

import argparse
import os
import sqlite3
import subprocess
import time

builddb = '/tmp/buildcounter.db'
gitpath = '/opt/buildbot/cache'

def create_builddb(remove=False):
    '''
    create build counter database if it does not already exist
    '''

    if remove and os.path.exists(builddb):
        os.remove(builddb)

    if os.path.exists(builddb):
        return

    db = sqlite3.connect(builddb, timeout=10)
    c = db.cursor()

    # Create tables
    c.execute("CREATE TABLE builds \
                 (repository text NOT NULL, \
                  branch text NOT NULL, \
                  reference text NOT NULL, \
                  starttime INTEGER, \
                  endtime INTEGER, \
                  buildcount INTEGER, \
                  PRIMARY KEY (repository, branch) )")

    c.execute("CREATE INDEX repository ON builds(repository)")

    # Save (commit) any changes
    db.commit()
    db.close()


def opendb(dbname, readonly=False):
    db = sqlite3.connect(dbname, timeout=20)
    db.execute('pragma journal_mode=wal;')
    if readonly:
        db.execute('pragma query_only=1;')
    return db


def open_builddb(readonly=False):
    return opendb(builddb, readonly)


def closedb(db):
    db.commit()
    db.close()


def git_check_output(path, command):
    git_cmd = ['git', '-C', path] + command
    return subprocess.check_output(git_cmd, encoding='utf-8', errors='ignore',
                                   stderr=subprocess.DEVNULL)


def git_run(path, command):
    git_cmd = ['git', '-C', path] + command
    return subprocess.run(git_cmd, check=True, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL)


def get_reference(repository, branch):
    repo = os.path.basename(repository)
    localdir = os.path.join(gitpath, os.path.splitext(repo)[0])

    try:
        os.mkdir(gitpath)
    except:
        pass

    if not os.path.isdir(localdir):
        oldpath = os.getcwd()
        os.chdir(gitpath)
        cmd = ['git', 'clone', repository]
        subprocess.run(cmd, check=True)
        os.chdir(oldpath)

    cmd = ['fetch', 'origin', branch]
    git_run(localdir, cmd)

    cmd = ['describe', 'FETCH_HEAD']
    reference = git_check_output(localdir, cmd)

    return reference.strip()


def build_started(c, repository, branch):

    q = """SELECT buildcount FROM builds
           WHERE repository IS ? AND branch IS ?"""
    c.execute(q, [repository, branch])
    if c.fetchone():
        q = """UPDATE builds SET buildcount = buildcount + 1
               WHERE repository IS ? AND branch IS ?"""
        c.execute(q, [repository, branch])
    else:
        reference = get_reference(repository, branch)
        q = """INSERT INTO builds
            (repository, branch, reference, starttime, endtime, buildcount)
            VALUES (?, ?, ?, ?, ?, ?)"""
        c.execute(q, [repository, branch, reference, int(time.time()), 0, 1])


def build_done(c, repository, branch):

    q = """UPDATE builds SET buildcount = buildcount - 1
           WHERE repository IS ? AND branch IS ? AND buildcount > 0"""
    c.execute(q, [repository, branch])
    # if buildcount is now 0, set/update endtime
    q = """UPDATE builds SET endtime = ?
           WHERE repository IS ? AND branch IS ? AND buildcount == 0"""
    c.execute(q, [int(time.time()), repository, branch])
    q = """SELECT SUM(buildcount) FROM builds"""
    c.execute(q)
    count, = c.fetchone()
    if count == 0:
        # No more active builds
	# Report builds and remove build entries from database
        q = """SELECT repository, branch, reference, starttime, endtime, buildcount FROM builds"""
        c.execute(q)
        for (repository, branch, reference, starttime, endtime, buildcount) in c.fetchall():
            with open('/tmp/buildcounter.log', 'a') as f:
                print("Build %s:%s started %s completed %s" %
                      (branch, reference,
                       time.asctime(time.localtime(starttime)),
                       time.asctime(time.localtime(endtime))), file=f)
            q = """DELETE FROM builds WHERE repository IS ? AND branch IS ?"""
            c.execute(q, [repository, branch])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Maintain database of active builds')
    parser.add_argument('-r', '--remove', action='store_true',
        help='Remove and re-create database')
    parser.add_argument('-s', '--start', action='store_true',
        help='Build started')
    parser.add_argument('-c', '--complete', action='store_true',
        help='Build complete')
    parser.add_argument('details', type=str, help='Repository, branch', nargs='*')

    args = parser.parse_args()

    if not args.start and not args.complete and not args.remove:
        parser.error('At leat one command option is necessary')

    if (args.start or args.complete) and len(args.details) != 2:
        parser.error('Must have both repository and branch names')

    create_builddb(args.remove)
    db = open_builddb()
    c = db.cursor()

    if args.start:
        build_started(c, args.details[0], args.details[1])
    if args.complete:
        build_done(c, args.details[0], args.details[1])

    closedb(db)
