Error subclass: #WodifyError
	instanceVariableNames: 'retryable'
	classVariableNames: ''
	package: 'Wodify'!

WodifyError comment: 'I am a failure to get the workouts that is worth telling the user (the config, a rejected login, a changed Wodify app). retryable says whether trying again in a minute may help (network trouble); a rejected password is not retried that soon, so as not to lock the account.'!

!WodifyError methodsFor: 'accessing'!
retryable
	^retryable == true
!
retryable: aBoolean
	retryable := aBoolean
! !
