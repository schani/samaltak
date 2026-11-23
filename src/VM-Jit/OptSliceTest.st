CLibrary subclass: #OptSliceTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

!OptSliceTest class methodsFor: 'declaring'!
headers
	^#('"opt_slice_test.h"')
! !

!OptSliceTest methodsFor: 'configuration'!
enabled
	<cMacro: 'bool OPT_SLICE_TEST_ENABLED'>
	^false
! !
