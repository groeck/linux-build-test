from buildbot import util
from twisted.internet import defer
from twisted.internet import reactor
from twisted.python import log

from buildbot.schedulers import base
from buildbot.util import NotABranch
from buildbot.changes import changes
from buildbot.changes import filter

import datetime
from dateutil import parser

def currentTimeInRange(range):
    start = parser.parse(range[0])
    end = parser.parse(range[1])
    now=datetime.datetime.now()
    if end < start:	# crosses midnight
        if end >= now:	# not yet ended
	    start -= datetime.timedelta(1)
	else:		# possibly not yet started
	    end += datetime.timedelta(1)
    return start <= now <= end

def timeToStart(start):
    start=parser.parse(start)
    now=datetime.datetime.now()
    if start > now:
	delta=start-now
	# delta includes fractions of seconds, so let's round up.
	return delta.days*24*60*60 + delta.seconds + 1
    return 0

class TimedSingleBranchScheduler(base.BaseScheduler):

    compare_attrs = ['timeRange', 'treeStableTimer', 'change_filter',
		      'fileIsImportant', 'collapseRequests',
		     'onlyImportant', 'reason']

    _reactor = reactor  # for tests

    fileIsImportant = None
    reason = ''

    def __init__(self, name, timeRange=["0:00","23:59:59"], treeStableTimer=None,
		 builderNames=None, branch=NotABranch, branches=NotABranch,
		 fileIsImportant=None, properties={}, categories=None,
		 reason="The %(classname)s scheduler named '%(name)s' triggered this build",
		 change_filter=None, onlyImportant=False,
		 collapseRequests=None,
		 **kwargs):
	log.msg("TimedSingleBranchScheduler %s: __init__" % self.name)

	base.BaseScheduler.__init__(self, name, builderNames, properties, **kwargs)

	self.timeRange = timeRange
	self._timed_change_lock = defer.DeferredLock()
	self._timed_change_timer = None

	self.treeStableTimer = treeStableTimer
	if fileIsImportant is not None:
	    self.fileIsImportant = fileIsImportant
	self.onlyImportant = onlyImportant
	self.collapseRequests = collapseRequests
	self.change_filter = self.getChangeFilter(branch=branch,
						  branches=branches, change_filter=change_filter,
						  categories=categories)

    def preStartConsumingChanges(self):
	# Hook for subclasses to setup before startConsumingChanges().
	return defer.succeed(None)

    def startService(self, _returnDeferred=False):
	log.msg("TimedSingleBranchScheduler %s: startService" % self.name)
        base.BaseScheduler.startService(self)

	d = self.preStartConsumingChanges()

	d.addCallback(lambda _:
	              self.startConsumingChanges(fileIsImportant=self.fileIsImportant,
		      change_filter=self.change_filter, onlyImportant=self.onlyImportant))

	d.addCallback(lambda _:
		      self.scanExistingClassifiedChanges())

	d.addErrback(log.err, "while starting TimedSingleBranchScheduler '%s'"
	             % self.name)

	if _returnDeferred:
	    return d  # only used in tests

    @util.deferredLocked('_timed_change_lock')
    def gotChange(self, change, important):
	log.msg("TimedSingleBranchScheduler %s[%d]: gotChange %d[%d]" %
			(self.name, self.objectid, change.number, important))
	if currentTimeInRange(self.timeRange) and not self._timed_change_timer:
	    return self.addBuildsetForChanges(reason=self.reason,
					      changeids=[change.number])

	d = self.master.db.schedulers.classifyChanges(
				self.objectid, {change.number: important})

	def set_timer(_):
	    log.msg("TimedSingleBranchScheduler %s[%d]: set_timer" % (self.name, self.objectid))
	    if not important and not self._timed_change_timer:
	        log.msg("TimedSingleBranchScheduler %s: set_timer abort(1)" % self.name)
		return

	    if self._timed_change_timer:
	        log.msg("TimedSingleBranchScheduler %s[%d]: canceling old timer" % (self.name, self.objectid))
		self._timed_change_timer.cancel()

	    def fire_timer():
	        log.msg("TimedSingleBranchScheduler %s[%d]: fire_timer" % (self.name, self.objectid))
		d = self.timedChangeTimerFired()
		d.addErrback(log.err, "while firing deferred timed timer")
	    self._timed_change_timer = self._reactor.callLater(
			timeToStart(self.timeRange[0]), fire_timer)
	d.addCallback(set_timer)
	return d

    @defer.inlineCallbacks
    def scanExistingClassifiedChanges(self):
        # call gotChange for each classified change.  This is called at startup
        # and is intended to re-start the build timer for any changes that
        # had not yet been built when the scheduler was stopped.

        # NOTE: this may double-call gotChange for changes that arrive just as
        # the scheduler starts up.  In practice, this doesn't hurt anything.
        classifications = \
            yield self.master.db.schedulers.getChangeClassifications(
                self.objectid)

        # call gotChange for each change, after first fetching it from the db
        for changeid, important in classifications.iteritems():
            chdict = yield self.master.db.changes.getChange(changeid)

            if not chdict:
                continue

            change = yield changes.Change.fromChdict(self.master, chdict)
            yield self.gotChange(change, important)

    def getChangeFilter(self, branch, branches, change_filter, categories):
	if branch is NotABranch and not change_filter:
	    config.error(
		"The 'branch' argument to TimedSingleBranchScheduler is mandatory unless change_filter is provided")
	elif branches is not NotABranch:
	    config.error(
		"the 'branches' argument is not allowed for TimedSingleBranchScheduler")

	return filter.ChangeFilter.fromSchedulerConstructorArgs(
		change_filter=change_filter, branch=branch,
		categories=categories)

    def getTimerNameForChange(self, change):
	return "only"

    @util.deferredLocked('_timed_change_lock')
    @defer.inlineCallbacks
    def timedChangeTimerFired(self):
	log.msg("TimedSingleBranchScheduler %s[%d]: timedChangeTimerFired" % (self.name, self.objectid))
	if not self._timed_change_timer:
	    log.msg("%s[%d]: timedChangeTimerFired: no timer, abort" % (self.name, self.objectid))
	    return
	del self._timed_change_timer
	self._timed_change_timer = None

	classifications = \
	    yield self.master.db.schedulers.getChangeClassifications(
		self.objectid)

	# just in case: databases do weird things sometimes!
	if not classifications:
	    log.msg("%s[%d]: timedChangeTimerFired: no classifications found, abort" %
			(self.name, self.objectid))
	    return

	changeids = sorted(classifications.keys())
	max_changeid = changeids[-1]
	# Verify that each change is still in the database; if it isn't,
	# addBuildsetForChanges() will bail out.
	# Use list() to copy the list for use as iterator; otherwise
	# the iterator fails if an element is removed from the list.
	for changeid in list(changeids):
	    chdict = yield self.master.db.changes.getChange(changeid)
	    if not chdict:
		log.msg("change ID: %d [dropped]" % changeid)
		changeids.remove(changeid)
	    else:
		log.msg("change ID: %d" % changeid)

	if changeids:
	    if self.collapseRequests:
		changeids = changeids[-1:]
	    yield self.addBuildsetForChanges(reason=self.reason,
					     changeids=changeids)

	log.msg("%s[%d]: Flushing change IDs up to %d" % (self.name, self.objectid, max_changeid))
	yield self.master.db.schedulers.flushChangeClassifications(
		self.objectid, less_than=max_changeid + 1)

    def stopService(self):
	d = base.BaseScheduler.stopService(self)

	@util.deferredLocked(self._timed_change_lock)
	def cancel_timer(_):
	    if self._timed_change_timer:
		self._timed_change_timer.cancel()
		del self._timed_change_timer
	d.addCallback(cancel_timer)
	return d

    def getPendingBuildTimes(self):
	if self._timed_change_timer:
	    t = self._timed_change_timer
	    if t.active():
	        return [t.getTime()]
	return []
