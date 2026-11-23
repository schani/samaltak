Magnitude subclass: #Time
	instanceVariableNames: 'seconds nanos'
	classVariableNames: ''
	package: 'System-Support'!

Time comment: 'I am a time of day (UTC; the VM has no time zone information): seconds since midnight plus nanoseconds. My class side gives access to the clocks: the monotonic millisecond and microsecond clocks for measuring, and UTC microseconds since 1970 for dates.'!

!Time methodsFor: 'accessing'!
hours
	^seconds // 3600
!
minutes
	^seconds \\ 3600 // 60
!
seconds
	^seconds \\ 60
!
nanoSecond
	^nanos
!
asSeconds
	"Answer the seconds since midnight."
	^seconds
!
setSeconds: secondCount nanos: nanoCount
	seconds := secondCount.
	nanos := nanoCount
! !

!Time methodsFor: 'comparing'!
< aTime
	^seconds < aTime asSeconds or: [seconds = aTime asSeconds and: [nanos < aTime nanoSecond]]
!
= aTime
	^self class == aTime class and: [seconds = aTime asSeconds and: [nanos = aTime nanoSecond]]
!
hash
	^(seconds hash hashMultiply + nanos hash) hashMultiply
! !

!Time methodsFor: 'printing'!
printOn: aStream
	"Print as hh:mm:ss."
	aStream
		nextPutAll: (self hours printPaddedWith: $0 to: 2); nextPut: $:;
		nextPutAll: (self minutes printPaddedWith: $0 to: 2); nextPut: $:;
		nextPutAll: (self seconds printPaddedWith: $0 to: 2)
! !

!Time class methodsFor: 'instance creation'!
now
	"Answer the current UTC time of day."
	| us |
	us := self utcMicroseconds.
	^self basicNew
		setSeconds: us // 1000000 \\ 86400
		nanos: us \\ 1000000 * 1000
!
fromSeconds: secondCount
	^self basicNew setSeconds: secondCount nanos: 0
!
hour: h minute: m second: s
	^self fromSeconds: h * 3600 + (m * 60) + s
! !

!Time class methodsFor: 'clocks'!
millisecondClockValue
	"Answer the monotonic millisecond clock (it restarts with the VM)."
	<primitive: 'millisecondClock'>
	^self primitiveFailed
!
millisecondClock
	^self millisecondClockValue
!
microsecondClockValue
	"Answer the monotonic microsecond clock."
	<primitive: 'microsecondClock'>
	^self primitiveFailed
!
utcMicroseconds
	"Answer the microseconds since 1970-01-01 00:00 UTC."
	<primitive: 'utcMicroseconds'>
	^self primitiveFailed
!
millisecondsToRun: aBlock
	"Answer how many milliseconds aBlock takes to evaluate."
	| start |
	start := self millisecondClockValue.
	aBlock value.
	^self millisecondClockValue - start
!
microsecondsToRun: aBlock
	| start |
	start := self microsecondClockValue.
	aBlock value.
	^self microsecondClockValue - start
!
millisecondsSince: aMillisecondClockValue
	^self millisecondClockValue - aMillisecondClockValue
! !
