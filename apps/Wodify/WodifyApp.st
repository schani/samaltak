Application subclass: #WodifyApp
	instanceVariableNames: 'card service'
	classVariableNames: ''
	package: 'Wodify'!

WodifyApp comment: 'I am the Omarchy desktop''s Wodify card as a window of its own: a WodifyCard of today''s and tomorrow''s workouts at your gym, kept current by a WodifyService (the config: ~/.config/omarchy/wodify.json), with the card''s settings from ~/.config/omarchy/desktop-cards.json (card "wodify"). The window''s height follows the workouts, up to 60 % of the screen''s; the rest scrolls.

	bin/samaltak run apps/Wodify
	WodifyApp run

A click opens the gym''s Wodify app in the browser (xdg-open), a middle click fetches again.'!

!WodifyApp methodsFor: 'accessing'!
title
	^'Wodify'
!
card
	^card
!
service
	^service
!
content
	card isNil ifTrue: [
		card := WodifyCard new.
		card onActivate: [self openInBrowser].
		card onRefresh: [service isNil ifFalse: [service refreshNow]]].
	^card
!
backgroundColor
	^self content background
!
settings
	^Omarchy cardSettings: 'wodify'
! !

!WodifyApp methodsFor: 'hooks'!
prepare
	| screen |
	OmarchyTheme install.
	service := WodifyService new.
	service refreshMinutes: (self settings at: 'refreshMinutes' ifAbsent: [30]).
	self content.
	"at most 60 % of the screen, as the card (its frame's 2-point border is Hyprland's here)"
	screen := Omarchy screenExtent.
	card maxHeight: ((screen isNil ifTrue: [1080] ifFalse: [screen y]) * 0.6) rounded - (2 * (card space: 2)).
	card settings: self settings.
	"the window opens with what was fetched last"
	service readCache.
	self show: service
!
started
	service onChange: [:s | window do: [card settings: self settings. self show: s. self fitToContent]].
	service start
!
stopped
	service isNil ifFalse: [service stop]
! !

!WodifyApp methodsFor: 'actions'!
show: aService
	card days: aService days ok: aService isOk error: aService error loading: aService isLoading today: aService today
!
openInBrowser
	"The gym's member app, as the card's click does."
	service url isNil ifFalse: [Omarchy launch: (Array with: 'xdg-open' with: service url)]
! !

!WodifyApp methodsFor: 'agent'!
agentContext
	"The Agent of my right-click menu also has my service (what it fetched, and fetching again)."
	^super agentContext bind: #service to: service; yourself
! !
