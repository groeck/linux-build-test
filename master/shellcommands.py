# -*- python -*-
# ex: set syntax=python:

from buildbot.steps.shell import ShellCommand
from buildbot.process.buildstep import LogLineObserver
from buildbot.status.builder import SUCCESS,WARNINGS,FAILURE,EXCEPTION,RETRY,SKIPPED

import re

passed = re.compile('Building (\S+):(\S+) \.\.\. passed$')
failed = re.compile('Building (\S+):(\S+) \.\.\. failed$')
skipped = re.compile('Building (\S+):(\S+) \.\.\. failed \(\S+\)')

passed_qemu = re.compile('Building (\S+):(\S+) \.+ running \.+ passed$')
failed_qemu = re.compile('Building (\S+):(\S+) .*?failed.*$')
skipped_qemu = re.compile('Building (\S+):(\S+) \.+ skipped$')

def lastStep(step):
    allSteps = step.build.getStatus().getSteps()
    last = allSteps[-1]
    (started, finished) = last.getTimes()
    return started

class RefShellCommand(ShellCommand):
    name = "buildcommand"
    command = [name]

    def __init__(self, **kwargs):
        ShellCommand.__init__(self, **kwargs)   # always upcall!
	self.ref = None
	self.traceback = False

    def createSummary(self, log):
        s = re.search("^Build reference: (\S+)$", log.getText(), re.MULTILINE)
	if s:
	    self.ref = s.group(1)
        s = re.search("\[ cut here \]", log.getText(), re.MULTILINE)
	if s:
	    self.traceback = True
        s = re.search("stack backtrace", log.getText(), re.MULTILINE)
	if s:
	    self.traceback = True
        s = re.search('(try booting with the "irqpoll" option)', log.getText(), re.MULTILINE)
	if s:
	    self.traceback = True

    def getText(self, cmd, results):
        if results != SKIPPED:
            text = ShellCommand.getText(self, cmd, results)
	else:
	    text = [ "skipped" ]
	if self.ref:
	    text.append(self.ref)
        return text

    def getText2(self, cmd, results):
        text = [ ]
	if self.ref:
	    text.append(self.ref)
        return text

    def maybeGetText2(self, cmd, results):
        # Add build reference if this step has been successful,
	# or if the previous step failed.
	text = [ ]
        if results == SUCCESS or results == WARNINGS:
	    text = [ "<br/>" ]
            text.extend(self.getText2(cmd, results))
	elif lastStep(self):
	    text = [ "<br/>" ]
	    text.extend(self.getText2(cmd, results))
        return text

    def evaluateCommand(self, cmd):
	if cmd.didFail():
	    return FAILURE
	if self.traceback:
	    return WARNINGS
	return SUCCESS

class AnalyzeBuildLog(LogLineObserver):
    def __init__(self, **kwargs):
        LogLineObserver.__init__(self, **kwargs)   # always upcall!
        self.numTotal = 0
        self.numPassed = 0
        self.numFailed = 0
        self.numSkipped = 0
        self.failed = []
    def outLineReceived(self, line):
	# Look for:
	# Building <arch>:<config> ... passed
	# Building <arch>:<config> ... failed
	# Building <arch:<config> ... failed (config) - skipping
        if line.startswith("Building "):
            self.numTotal += 1
	    if passed.match(line):
                self.numPassed += 1
                self.step.setProgress('pass', self.numPassed)
	    if failed.match(line):
                self.numFailed += 1
                self.step.setProgress('fail', self.numFailed)
                self.failed.append(failed.findall(line))
	    if skipped.match(line):
                self.numSkipped += 1
                self.step.setProgress('skipped', self.numSkipped)

class StableBuildCommand(RefShellCommand):
    name = "buildcommand"
    command = [name]

    def __init__(self, **kwargs):
        RefShellCommand.__init__(self, **kwargs)   # always upcall!
        self.counter = AnalyzeBuildLog()
        self.addLogObserver('stdio', self.counter)
        self.progressMetrics += ('builds', 'pass', 'fail', 'skipped',)

    def getText(self, cmd, results):
        text = RefShellCommand.getText(self, cmd, results)
	# if results == SKIPPED:
	#     return text
	text.append("total: " + str(self.counter.numTotal))
        if self.counter.numPassed > 0:
            text.append("pass: " + str(self.counter.numPassed))
        if self.counter.numSkipped > 0:
            text.append("skipped: " + str(self.counter.numSkipped))
        if self.counter.numFailed > 0:
            text.append("fail: " + str(self.counter.numFailed))
	    # text.append("<!-- [")
            # for elem in self.counter.failed:
	    #     text.append(str(elem[0][0]) + ":" + str(elem[0][1]) + " ")
	    # text.append("] -->")
        return text

    def getText2(self, cmd, results):
        text = RefShellCommand.getText2(self, cmd, results)
	# if results == SKIPPED:
	#     return text
	text.append("<br>");
	text.append("total: " + str(self.counter.numTotal))
        if self.counter.numPassed > 0:
            text.append("pass: " + str(self.counter.numPassed))
        if self.counter.numSkipped > 0:
            text.append("skipped: " + str(self.counter.numSkipped))
        if self.counter.numFailed > 0:
            text.append("fail: " + str(self.counter.numFailed))
	    text.append("<!-- ")
            for elem in self.counter.failed:
	        text.append(str(elem[0][0]) + ":" + str(elem[0][1]) + " ")
	    text.append("-->")
        return text

    def maybeGetText2(self, cmd, results):
	return self.getText2(cmd, results)

    def evaluateCommand(self, cmd):
        if self.counter.numFailed > 0:
	    if self.counter.numPassed == 0:
	        return FAILURE
            return WARNINGS
        else:
	    if self.counter.numPassed == 0:
	        self.build.result = SKIPPED
		return SKIPPED
            return SUCCESS

class AnalyzeQemuBuildLog(LogLineObserver):
    def __init__(self, **kwargs):
        LogLineObserver.__init__(self, **kwargs)   # always upcall!
        self.numTotal = 0
        self.numPassed = 0
        self.numFailed = 0
        self.numSkipped = 0
        self.failed = []
    def outLineReceived(self, line):
	# Look for:
	# Building <arch>:<config> .+ running .+ passed
	# Building <arch>:<config> .* failed.*
        if passed_qemu.match(line) or failed_qemu.match(line) or skipped_qemu.match(line):
            self.numTotal += 1
	    if passed_qemu.match(line):
                self.numPassed += 1
                self.step.setProgress('pass', self.numPassed)
	    if failed_qemu.match(line):
                self.numFailed += 1
                self.step.setProgress('fail', self.numFailed)
                self.failed.append(failed_qemu.findall(line))
            if skipped_qemu.match(line):
	        self.numSkipped += 1
                self.step.setProgress('skipped', self.numSkipped)

class QemuBuildCommand(RefShellCommand):
    name = "qemubuildcommand"
    command = [name]

    def __init__(self, **kwargs):
        RefShellCommand.__init__(self, **kwargs)   # always upcall!
        self.counter = AnalyzeQemuBuildLog()
        self.addLogObserver('stdio', self.counter)
        self.progressMetrics += ('builds', 'pass', 'fail', 'skipped', )

    def getText(self, cmd, results):
	hidden = self._maybeEvaluate(self.hideStepIf, results, self)
	if hidden:
	    return ""
        text = RefShellCommand.getText(self, cmd, results)
	# if results == SKIPPED:
	#     return text
	text.append("total: " + str(self.counter.numTotal))
        if self.counter.numPassed > 0:
            text.append("pass: " + str(self.counter.numPassed))
        if self.counter.numSkipped > 0:
            text.append("skipped: " + str(self.counter.numSkipped))
        if self.counter.numFailed > 0:
            text.append("fail: " + str(self.counter.numFailed))
	    # text.append("<!-- [")
            # for elem in self.counter.failed:
	    #     text.append(str(elem[0][0]) + ":" + str(elem[0][1]) + " ")
	    # text.append("] -->")
        return text

    def getText2(self, cmd, results):
	hidden = self._maybeEvaluate(self.hideStepIf, results, self)
	if hidden:
	    return ""
        text = RefShellCommand.getText2(self, cmd, results)
	# if results == SKIPPED:
	#     return text
	text.append("<br>");
	text.append("total: " + str(self.counter.numTotal))
        if self.counter.numPassed > 0:
            text.append("pass: " + str(self.counter.numPassed))
        if self.counter.numSkipped > 0:
            text.append("skipped: " + str(self.counter.numSkipped))
        if self.counter.numFailed > 0:
            text.append("fail: " + str(self.counter.numFailed))
	    text.append("<!-- ")
            for elem in self.counter.failed:
	        text.append(str(elem[0][0]) + ":" + str(elem[0][1]) + " ")
	    text.append("-->")
        return text

    def maybeGetText2(self, cmd, results):
	return self.getText2(cmd, results)

    def evaluateCommand(self, cmd):
        result = RefShellCommand.evaluateCommand(self, cmd)
        if self.counter.numFailed > 0:
	    if self.counter.numPassed == 0:
	        return FAILURE
            return WARNINGS
        else:
	    if self.counter.numPassed == 0:
	        self.build.result = SKIPPED
		return SKIPPED
            return result
