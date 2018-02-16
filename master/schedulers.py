from buildbot import util
from twisted.internet import defer
from twisted.python import log

from buildbot.schedulers.basic import BaseBasicScheduler
from buildbot.schedulers import base
# from buildbot.schedulers.basic import AnyBranchScheduler
from buildbot.util import NotABranch
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

class TimedSingleBranchScheduler(BaseBasicScheduler):

    compare_attrs = ['timeRange', 'treeStableTimer']

    def __init__(self, name, timeRange=["0:00","23:59:59"], treeStableTimer=None, **kwargs):
	log.msg("TimedSingleBranchScheduler %s: __init__" % self.name)
	self.timeRange = timeRange
	self._timed_change_lock = defer.DeferredLock()
	self._timed_change_timer = None
	BaseBasicScheduler.__init__(self, name, **kwargs)

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
	log.msg("TimedSingleBranchScheduler %s: gotChange %d:%d [%d]" %
			(self.name, self.objectid, change.number, important))
	if currentTimeInRange(self.timeRange) and not self._timed_change_timer:
	    return self.addBuildsetForChanges(reason=self.reason,
					      changeids=[change.number])

	d = self.master.db.schedulers.classifyChanges(
				self.objectid, {change.number: important})

	def set_timer(_):
	    log.msg("TimedSingleBranchScheduler %s: set_timer" % self.name)
	    if not important and not self._timed_change_timer:
	        log.msg("TimedSingleBranchScheduler %s: set_timer abort(1)" % self.name)
		return

	    if self._timed_change_timer:
	        log.msg("TimedSingleBranchScheduler %s: canceling old timer" % self.name)
		self._timed_change_timer.cancel()

	    def fire_timer():
	        log.msg("TimedSingleBranchScheduler %s: fire_timer" % self.name)
		d = self.timedChangeTimerFired()
		d.addErrback(log.err, "while firing deferred timed timer")
	    self._timed_change_timer = self._reactor.callLater(
			timeToStart(self.timeRange[0]), fire_timer)
	d.addCallback(set_timer)
	return d

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
	log.msg("TimedSingleBranchScheduler %s: timedChangeTimerFired (%d)" % (self.name, self.objectid))
	if not self._timed_change_timer:
	    log.msg("%s: timedChangeTimerFired: no timer, abort" % self.name)
	    return
	del self._timed_change_timer
	self._timed_change_timer = None

	classifications = \
	    yield self.master.db.schedulers.getChangeClassifications(
		self.objectid)

	# just in case: databases do weird things sometimes!
	if not classifications:
	    log.msg("%s: timedChangeTimerFired: classifications for objectid %d not found, abort" %
			(self.name, self.objectid))
	    return

	changeids = sorted(classifications.keys())
	for changeid in changeids:
	    log.msg("change ID: %d" % changeid)
	yield self.addBuildsetForChanges(reason=self.reason,
					 changeids=changeids)

	max_changeid = changeids[-1]
	yield self.master.db.schedulers.flushChangeClassifications(
		self.objectid, less_than=max_changeid + 1)

    def stopService(self):
	d = BaseBasicScheduler.stopService(self)

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
