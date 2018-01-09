from buildbot import util
from twisted.internet import defer
from twisted.python import log

from buildbot.schedulers.basic import SingleBranchScheduler
# from buildbot.schedulers.basic import AnyBranchScheduler

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

class TimedSingleBranchScheduler(SingleBranchScheduler):

    def __init__(self, name, timeRange=["0:00","23:59:59"], **kwargs):
	self.timeRange = timeRange
	self._timed_change_lock = defer.DeferredLock()
	self._timed_change_timer = None
	SingleBranchScheduler.__init__(self, name, **kwargs)

    @util.deferredLocked('_timed_change_lock')
    def gotChange(self, change, important):
	if currentTimeInRange(self.timeRange) and not self._timed_change_timer:
	    return SingleBranchScheduler.gotChange(self, change, important)

	d = self.master.db.schedulers.classifyChanges(
				self.objectid, {change.number: important})

	def set_timer(_):
	    if not important and not self._timed_change_timer:
		return

	    if self._timed_change_timer:
		self._timed_change_timer.cancel()

	    def fire_timer():
		d = self.timedChangeTimerFired(change, important)
		d.addErrback(log.err, "while firing deferred timed timer")
	    self._timed_change_timer = self._reactor.callLater(
			timeToStart(self.timeRange[0]), fire_timer)
	d.addCallback(set_timer)
	return d

    @util.deferredLocked('_timed_change_lock')
    @defer.inlineCallbacks
    def timedChangeTimerFired(self, change, important):
	if not self._timed_change_timer:
	    return
	del self._timed_change_timer
	self._timed_change_timer = None

	classifications = \
	    yield self.master.db.schedulers.getChangeClassifications(
		self.objectid)

	# just in case: databases do weird things sometimes!
	if not classifications:
	    return

	changeids = sorted(classifications.keys())
	yield self.addBuildsetForChanges(reason=self.reason,
					 changeids=changeids)

	max_changeid = changeids[-1]
	yield self.master.db.schedulers.flushChangeClassifications(
		self.objectid, less_than=max_changeid + 1)

    def stopService(self):
	d = SingleBranchScheduler.stopService(self)

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
