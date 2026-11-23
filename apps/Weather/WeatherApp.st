Application subclass: #WeatherApp
	instanceVariableNames: 'card service'
	classVariableNames: ''
	package: 'Weather'!

WeatherApp comment: 'I am the weather of the Omarchy desktop card as a window of its own: a WeatherCard kept current by a WeatherService, in the Omarchy theme (colors, typeface and type scale follow omarchy theme set and omarchy font set). Imperial units where the locale is en_US, en_LR or my.

	bin/samaltak run apps/Weather
	WeatherApp run

A click opens the bar''s weather panel (omarchy-shell), a middle click fetches again.'!

!WeatherApp methodsFor: 'accessing'!
title
	^'Weather'
!
card
	^card
!
service
	^service
!
content
	card isNil ifTrue: [
		card := WeatherCard new.
		card imperial: WeatherReport environmentUsesImperial.
		card onActivate: [self openPanel].
		card onRefresh: [service isNil ifFalse: [service refreshNow]]].
	^card
!
backgroundColor
	^self content background
! !

!WeatherApp methodsFor: 'hooks'!
prepare
	OmarchyTheme install
!
started
	service := WeatherService new.
	service onChange: [:s | window do: [card report: s report location: s location error: s error]].
	service start
!
stopped
	service isNil ifFalse: [service stop]
! !

!WeatherApp methodsFor: 'actions'!
openPanel
	"The bar's weather panel, as the desktop card's click does."
	[(OSProcess command: 'omarchy-shell -q shell toggle omarchy.weather') start; wait]
		forkAt: Processor userBackgroundPriority
! !

!WeatherApp methodsFor: 'agent'!
agentContext
	"The Agent of my right-click menu also has my service (what it fetched, and fetching again)."
	^super agentContext bind: #service to: service; yourself
! !
