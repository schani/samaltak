TestCase subclass: #AgentsTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Agents'!

AgentsTest comment: 'Tests the agents app on records written to a scratch directory: which agents show and in what order, windows named, timed and paced as the bar does, the card''s formats, and the card drawing them.

	bin/samaltak test apps/Agents'!

!AgentsTest methodsFor: 'support'!
writeRecords
	| dir |
	dir := self scratchDirectory / 'usage'.
	Directory create: dir.
	File writeText: '{"id": "codex", "name": "Codex", "tierLabel": "Pro 200", "limits": [{"label": "Weekly (7-day)", "percent": 0.5, "resetsAt": "2026-11-29T20:00:00+00:00"}]}' to: dir / 'codex.json'.
	File writeText: '{"id": "claude", "name": "Claude Code", "tierLabel": "Max 20x", "limitsStale": true, "limits": [{"label": "5-hour session", "percent": 0.95, "resetsAt": "2026-11-22T20:00:00Z"}, {"label": "Fable Weekly", "title": "Fable Weekly", "percent": 0.02, "resetsAt": "2026-11-28T18:00:00Z"}]}' to: dir / 'claude.json'.
	File writeText: '{"id": "zz", "name": "Prepaid", "limits": [], "balance": {"remaining": 1234.5, "funded": 2000, "currency": "eur"}}' to: dir / 'zz.json'.
	File writeText: '{"id": "kimi", "name": "Kimi", "limits": []}' to: dir / 'kimi.json'.
	File writeText: 'not json' to: dir / 'broken.json'.
	^dir
! !

!AgentsTest methodsFor: 'tests'!
testRecordsShownInTheBarsOrder
	| dir usages |
	dir := self writeRecords.
	usages := AgentUsage recordsIn: dir hiding: #().
	self assert: (usages collect: [:u | u id]) equals: #('claude' 'codex' 'zz').
	usages := AgentUsage recordsIn: dir hiding: #('codex').
	self assert: (usages collect: [:u | u id]) equals: #('claude' 'zz').
	self assert: (AgentUsage recordsIn: dir / 'missing' hiding: #()) isEmpty
!
testWindows
	| dir claude wins now |
	dir := self writeRecords.
	claude := (AgentUsage recordsIn: dir hiding: #()) first.
	self assert: claude isStale.
	"2026-11-22T18:00:00Z: two hours before the session resets"
	now := 1795370400.
	wins := claude windowsAt: now.
	self assert: (wins collect: [:w | w first]) equals: #('Session' 'Fable Weekly').
	self assert: (wins first at: 2) equals: 0.95.
	self assert: (wins first at: 3) equals: 7200.
	self assert: (wins first at: 4) equals: 3 / 5.
	"a week's span named by the title"
	self assert: (wins last at: 4) equals: 1 / 7.
	"past its reset a window is empty and unpaced"
	wins := claude windowsAt: now + 7300.
	self assert: (wins first at: 2) equals: 0.
	self assert: (wins first at: 3) equals: -1.
	self assert: (wins first at: 4) equals: -1
!
testWindowNames
	self assert: (AgentUsage windowSpan: 'Weekly (7-day)') equals: 7 * 86400.
	self assert: (AgentUsage windowSpan: 'Monthly') equals: 30 * 86400.
	self assert: (AgentUsage windowSpan: '5-hour session') equals: 5 * 3600.
	self assert: (AgentUsage windowSpan: '5h') equals: 5 * 3600.
	self assert: (AgentUsage windowSpan: '5 hours') equals: 0.
	self assert: (AgentUsage windowSpan: '30 min burst') equals: 30 * 60.
	self assert: (AgentUsage windowSpan: 'Daily') equals: 0.
	self assert: (AgentUsage windowTitle: 'Weekly (7-day)') equals: 'Weekly'.
	self assert: (AgentUsage windowTitle: '5-hour') equals: 'Session'.
	self assert: (AgentUsage windowTitle: 'Premium requests (beta)') equals: 'Premium requests'.
	self assert: (AgentUsage windowTitle: '') equals: 'Limit'
!
testFormats
	self assert: (AgentUsage duration: -1) equals: ''.
	self assert: (AgentUsage duration: 42 * 60) equals: '42m'.
	self assert: (AgentUsage duration: 3 * 3600 + 300) equals: '3h 5m'.
	self assert: (AgentUsage duration: 6 * 86400 + (4 * 3600) + 100) equals: '6d 4h'.
	self assert: (AgentUsage percent: 0.034) equals: '3%'.
	self assert: (AgentUsage percent: 12.5) equals: '1,250%'.
	self assert: (AgentUsage money: 1234.5 currency: 'eur') equals: '€1,234.50'.
	self assert: (AgentUsage money: 5 currency: 'CHF') equals: 'CHF 5.00'.
	self assert: (AgentUsage money: 0.5 currency: nil) equals: '$0.50'
!
testCardDraws
	| card canvas usages h |
	usages := AgentUsage recordsIn: self writeRecords hiding: #().
	card := AgentsCard new.
	h := card preferredExtent y.
	card usages: usages at: 1795370400.
	self assert: card preferredExtent y > h.
	card bounds: (0 @ 0 extent: card preferredExtent).
	canvas := Canvas extent: card preferredExtent scale: 1.
	card drawOn: canvas.
	self assert: card remoteLabel equals: 'Claude Code, Codex, Prepaid'
! !
