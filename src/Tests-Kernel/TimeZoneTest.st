TestCase subclass: #TimeZoneTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

TimeZoneTest comment: 'Tests TimeZone: POSIX rules (the footer of a TZif file) against offsets Python''s zoneinfo gives, a TZif file of the system''s zoneinfo when there is one, and reading ISO 8601 times.'!

!TimeZoneTest methodsFor: 'tests'!
testPosixRules
	| la vienna sydney kolkata |
	la := TimeZone fromRule: 'PST8PDT,M3.2.0,M11.1.0'.
	"2026-03-08 09:59:59 UTC is 01:59:59 PST, a second later it is 03:00 PDT"
	self assert: (la offsetAt: 1772963999) equals: -28800.
	self assert: (la offsetAt: 1772964000) equals: -25200.
	self assert: (la offsetAt: 1793500000) equals: -25200.
	self assert: (la offsetAt: 2500000000) equals: -25200.
	self assert: (la offsetAt: 4000000000) equals: -25200.
	self assert: (la offsetAt: 1795960800) equals: -28800.
	vienna := TimeZone fromRule: 'CET-1CEST,M3.5.0,M10.5.0/3'.
	self assert: (vienna offsetAt: 2200000000) equals: 7200.
	self assert: (vienna offsetAt: 2500000000) equals: 3600.
	"the southern hemisphere: daylight time across the new year"
	sydney := TimeZone fromRule: 'AEST-10AEDT,M10.1.0,M4.1.0/3'.
	self assert: (sydney offsetAt: 2500000000) equals: 39600.
	self assert: (sydney offsetAt: 2200000000) equals: 36000.
	kolkata := TimeZone fromRule: 'IST-5:30'.
	self assert: (kolkata offsetAt: 1700000000) equals: 19800.
	self assert: (TimeZone fromRule: 'not a rule') name equals: 'UTC'
!
testZoneinfoFile
	| path la |
	path := '/usr/share/zoneinfo/America/Los_Angeles'.
	(File exists: path) ifFalse: [^self skip: 'no zoneinfo'].
	la := TimeZone fromFile: path.
	self assert: (#(0 1700000000 1773000000 1793500000 2200000000 4000000000) collect: [:t | la offsetAt: t])
		equals: #(-28800 -28800 -25200 -25200 -25200 -25200).
	self assert: (la dateAt: 1795960800) printString equals: '2026-11-29'.
	self assert: (la dateAt: 1795910400) printString equals: '2026-11-28'
!
testISO8601
	| utc |
	utc := TimeZone utc.
	self assert: (utc utcSecondsOf: '2026-11-29T14:00:00.136034+00:00') equals: 1795960800 + 0.136034.
	self assert: (utc utcSecondsOf: '2026-11-29T20:31:06Z') equals: 1795984266.
	self assert: (utc utcSecondsOf: '2026-11-29T12:31:06-08:00') equals: 1795984266.
	self assert: (utc utcSecondsOf: '2026-07-01T12:00:00+0530') equals: 1782887400.
	self assert: (utc utcSecondsOf: '2026-11-29') equals: 1795910400.
	"without an offset a time is local"
	self assert: ((TimeZone fromRule: 'PST8PDT,M3.2.0,M11.1.0') utcSecondsOf: '2026-11-29T12:31:06') equals: 1795984266.
	self assert: (utc utcSecondsOf: 'garbage') isNil.
	self assert: (utc utcSecondsOf: nil) isNil
! !
