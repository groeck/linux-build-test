from buildbot import util
from twisted.internet import defer
from twisted.python import log

from buildbot.schedulers.basic import SingleBranchScheduler
from buildbot.schedulers.basic import AnyBranchScheduler

import datetime
from dateutil import parser

def currentTimeInRange(range):
    start = parser.parse(range[0])
    end = parser.parse(range[1])
    now=datetime.datetime.now()
    if end < start:
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
	log.msg("TimedSingleBranchScheduler %s: initializing" % self.name)
	SingleBranchScheduler.__init__(self, name, **kwargs)
	log.msg("TimedSingleBranchScheduler %s: initialization complete" % self.name)

    @util.deferredLocked('_timed_change_lock')
    def gotChange(self, change, important):
	log.msg("TimedSingleBranchScheduler: Handling change: %s, important=%d"
		% (change, important))
	if currentTimeInRange(self.timeRange):
	    log.msg("Time in range. Calling SingleBranchScheduler.gotChange.")
	    return SingleBranchScheduler.gotChange(self, change, important)

	log.msg("Time not in range. Scheduling %d seconds from now." %
		timeToStart(self.timeRange[0]))

	d = self.master.db.schedulers.classifyChanges(
				self.objectid, {change.number: important})

	def set_timer(_):
	    if not important and not self._timed_change_timer:
		return

	    if self._timed_change_timer:
		self._timed_change_timer.cancel()

	    def fire_timer():
		d = self.timedChangeTimerFired(change, important)
		d.addCallback(log.msg, "deferred timed timer fired")
		d.addErrback(log.err, "while firing deferred timed timer")
	    self._timed_change_timer = self._reactor.callLater(
			timeToStart(self.timeRange[0]), fire_timer)
	d.addCallback(set_timer)
	return d

    @util.deferredLocked('_timed_change_lock')
    @defer.inlineCallbacks
    def timedChangeTimerFired(self, change, important):
	log.msg("timedChangeTimerFired: change=%s, important=%d" %
		(change, important))
	if not self._timed_change_timer:
	    log.msg("no timer, aborting")
	    return
	del self._timed_change_timer

	yield SingleBranchScheduler.gotChange(self, change, important)

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
	t = self._timed_change_timer
	if t and t.active():
	    return [t.getTime()]
	return []

class TimedAnyBranchScheduler(AnyBranchScheduler):

    def __init__(self, name, timeRange=["0:00","23:59:59"], **kwargs):
	self.timeRange = timeRange
	self._timed_change_lock = defer.DeferredLock()
	self._timed_change_timer = None
	log.msg("TimedAnyBranchScheduler %s: initializing" % self.name)
	AnyBranchScheduler.__init__(self, name, **kwargs)
	log.msg("TimedAnyBranchScheduler %s: initialization complete" % self.name)

    @util.deferredLocked('_timed_change_lock')
    def gotChange(self, change, important):
	log.msg("TimedAnyBranchScheduler: Handling change: %s, important=%d"
		% (change, important))
	if currentTimeInRange(self.timeRange):
	    log.msg("Time in range. Calling AnyBranchScheduler.gotChange.")
	    return AnyBranchScheduler.gotChange(self, change, important)

	log.msg("Time not in range. Scheduling %d seconds from now." %
		timeToStart(self.timeRange[0]))

	d = self.master.db.schedulers.classifyChanges(
				self.objectid, {change.number: important})

	def set_timer(_):
	    if not important and not self._timed_change_timer:
		return

	    if self._timed_change_timer:
		self._timed_change_timer.cancel()

	    def fire_timer():
		d = self.timedChangeTimerFired(change, important)
		d.addCallback(log.msg, "deferred timed timer fired")
		d.addErrback(log.err, "while firing deferred timed timer")
	    self._timed_change_timer = self._reactor.callLater(
				timeToStart(self.timeRange[0]), fire_timer)
	d.addCallback(set_timer)
	return d

    @util.deferredLocked('_timed_change_lock')
    @defer.inlineCallbacks
    def timedChangeTimerFired(self, change, important):
	log.msg("timedChangeTimerFired: change=%s, important=%d" %
		(change, important))
	if not self._timed_change_timer:
	    log.msg("no timer, aborting")
	    return
	del self._timed_change_timer

	yield AnyBranchScheduler.gotChange(self, change, important)

    def stopService(self):
	d = AnyBranchScheduler.stopService(self)

	@util.deferredLocked(self._timed_change_lock)
	def cancel_timer(_):
	    if self._timed_change_timer:
		self._timed_change_timer.cancel()
		del self._timed_change_timer
	d.addCallback(cancel_timer)
	return d

    def getPendingBuildTimes(self):
	t = self._timed_change_timer
	if t and t.active():
	    return [t.getTime()]
	return []
