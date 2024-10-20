# -*- python -*-
# ex: set syntax=python:

from buildbot.steps.shell import ShellCommand
from buildbot.process.buildstep import LogLineObserver
from buildbot.status.builder import SUCCESS,WARNINGS,FAILURE,EXCEPTION,RETRY,SKIPPED

import re

passed = re.compile('Building (\S+):(\S+) \.\.\. passed$')
failed = re.compile('Building (\S+):(\S+) \.\.\. failed$')
skipped = re.compile('Building (\S+):(\S+) \.\.\. failed \(\S+\)')

current_qemu = re.compile('Building ([^:\s]+):([^:\s]+):(\S+) \.+ running [\.R]+')
passed_qemu = re.compile('Building (\S+):(\S+) \.+ running [\.R]+ passed$')
failed_qemu = re.compile('Building (\S+):(\S+) .*?failed.*$')
skipped_qemu = re.compile('Building (\S+):(\S+) \.+ skipped.*$')

kunit_result = re.compile('(?:\[ *\d+\.\d+\](?:\[ *T\d+\])? +)?# ([^:]+): pass:(\d+) fail:(\d+) skip:(\d+) total:\d+$')

def lastStep(step):
    allSteps = step.build.getStatus().getSteps()
    last = allSteps[-1]
    (started, finished) = last.getTimes()
    return started

class GetBuildReference(LogLineObserver):
    ref = None
    _re_ref = re.compile(r'^Build reference: (\S+)$')

    def __init__(self, **kwargs):
	LogLineObserver.__init__(self, **kwargs)   # always upcall!

    def outLineReceived(self, line):
	s = self._re_ref.search(line.strip())
	if s:
	    self.step.setProperty('reference', s.group(1))
	    self.step.setProgress('ref', 1)

class RefShellCommand(ShellCommand):
    name = "buildcommand"
    command = [name]

    def __init__(self, **kwargs):
	ShellCommand.__init__(self, **kwargs)   # always upcall!
	self.reference = GetBuildReference()
	self.addLogObserver('stdio', self.reference)
	self.progressMetrics += ('ref',)

    def getText(self, cmd, results):
        # if results != SKIPPED:
        #     text = ShellCommand.getText(self, cmd, results)
	# else:
	#     text = [ "skipped" ]
        text = ShellCommand.getText(self, cmd, results)
        ref = self.getProperty('reference', None)
        if ref:
            text.append(ref)
        return text

    def getText2(self, cmd, results):
        text = [ ]
        ref = self.getProperty('reference', None)
        if ref:
            text.append(ref)
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

#    def evaluateCommand(self, cmd):
#	if cmd.didFail():
#	    return FAILURE
#	return SUCCESS

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
	text.append("<br>")
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
        self.numKunitPassed = 0
        self.numKunitFailed = 0
        self.numKunitSkipped = 0
        self.tracebacks = False
        self.current = None
        self.failed = []
        self.kunit_failed = []
    def outLineReceived(self, line):
        # Look for:
        # Building <arch>:<machine>:<config> .+ running .+ passed
        # Building <arch>:<machine>:<config> .* failed.*
        # save architecture and machine in self.current for later use
        # Make sure that '#" is not in the architecture or machine name
        # because that is used as separator later on.
        current = current_qemu.match(line)
        if current:
            self.current = [current.group(1).replace('#','_'), current.group(2).replace('#','_')]
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
	if line.find('[ cut here ]') != -1:
	    self.tracebacks = True
	elif line.find('Call Trace:') != -1:
	    self.tracebacks = True
	elif line.find('Call trace:') != -1:
	    self.tracebacks = True
	elif line.find('stack backtrace') != -1:
	    self.tracebacks = True
	elif line.find('Kernel panic') != -1:
	    self.tracebacks = True
	elif line.find('show_stack') != -1:
	    self.tracebacks = True
	elif line.find('(try booting with the "irqpoll" option)') != -1:
            self.tracebacks = True
        kunit = kunit_result.match(line)
        if kunit:
            # count totals but add individual test results to output
            if kunit.group(1) == 'Totals':
                self.numKunitPassed += int(kunit.group(2))
                self.numKunitFailed += int(kunit.group(3))
                self.numKunitSkipped += int(kunit.group(4))
            elif self.current and int(kunit.group(3)) > 0:
                new = self.current + [kunit.group(1).replace('#','_')]
                if new not in self.kunit_failed:
                    self.kunit_failed.append(new)

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
        if self.counter.numKunitFailed or self.counter.numKunitPassed or self.counter.numKunitSkipped:
            text.append("kunit: ")
            if self.counter.numKunitPassed:
                text.append("pass: " + str(self.counter.numKunitPassed))
            if self.counter.numKunitSkipped:
                text.append("skipped: " + str(self.counter.numKunitSkipped))
            if self.counter.numKunitFailed:
                text.append("fail: " + str(self.counter.numKunitFailed))
        return text

    def getText2(self, cmd, results):
	hidden = self._maybeEvaluate(self.hideStepIf, results, self)
	if hidden:
	    return ""
        text = RefShellCommand.getText2(self, cmd, results)
	# if results == SKIPPED:
	#     return text
	text.append("<br>")
	text.append("total: " + str(self.counter.numTotal))
        if self.counter.numPassed > 0:
            text.append("pass: " + str(self.counter.numPassed))
        if self.counter.numSkipped > 0:
            text.append("skipped: " + str(self.counter.numSkipped))
        if self.counter.numFailed > 0:
            text.append("fail: " + str(self.counter.numFailed))
	    text.append("<!-- fail ")
            for elem in self.counter.failed:
	        text.append(str(elem[0][0]) + ":" + str(elem[0][1]) + " ")
	    text.append("fail -->")
        if self.counter.numKunitFailed or self.counter.numKunitPassed or self.counter.numKunitSkipped:
            text.append("<br>")
            text.append("kunit: ")
            if self.counter.numKunitPassed:
                text.append("pass: " + str(self.counter.numKunitPassed))
            if self.counter.numKunitSkipped:
                text.append("skipped: " + str(self.counter.numKunitSkipped))
            if self.counter.numKunitFailed:
                text.append("fail: " + str(self.counter.numKunitFailed))
                text.append("<!-- kunit ")
                elems = []
                for elem in self.counter.kunit_failed:
                    elems.append(':'.join(elem))
                text.append('#'.join(elems))
                text.append(" kunit -->")
        return text

    def maybeGetText2(self, cmd, results):
	return self.getText2(cmd, results)

    def evaluateCommand(self, cmd):
        c = self.counter
        if c.numFailed > 0:
            if c.numPassed == 0:
                result = FAILURE
            else:
                result = WARNINGS
        elif c.numPassed == 0:
            self.build.result = SKIPPED
            result = SKIPPED
        elif c.tracebacks:
            result = WARNINGS
        else:
            result = SUCCESS

        return result
