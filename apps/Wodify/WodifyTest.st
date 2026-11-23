TestCase subclass: #WodifyTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Wodify'!

WodifyTest comment: 'Tests the Wodify app without the network: Wodify''s HTML as text, level blocks and hidden parts, finding an action''s apiVersion in the app''s scripts, the CSRF token, shaping a day from a response, the offline cache, and the card''s days, labels and layout.

	bin/samaltak test apps/Wodify'!

!WodifyTest methodsFor: 'fixtures'!
response
	"A GetAllWorkoutData response as Wodify sends it (made up)."
	^JSON parse: '{"ResponseWOD": {"ResponseWorkout": {"Name": "CrossFit - Mon, Nov 23", "Comments": "<p>Scale as needed</p>",
		"Notes": "", "WorkoutComponents": {"List": [
			{"IsSection": true, "Name": "Warm Up"},
			{"Name": "Row", "Description": "500m<br/>easy"},
			{"IsSection": true, "Name": "Strength"},
			{"Name": "Back Squat", "Description": "", "MeasureRepScheme": "5x5", "PrefixText": "Every 2:00", "Comment": "<i>Build</i>"},
			{"Name": "", "Description": ""},
			{"Name": "Metcon", "Description": "- RX -<br>21-15-9<br>- BEGINNER -<br>15-12-9", "Comment": ""}]}}},
		"Response_Profile": {"Phone": "555"}}'
!
cardWithDays
	| card |
	card := WodifyCard new.
	card settings: (JSON parse: '{"hide": ["warmup", "Beginner"]}').
	card days: (Array
			with: (WodifyDay fromJSON: (JSON parse: '{"date": "2026-11-22", "title": "Yesterday", "items": []}'))
			with: (WodifyDay date: (Date year: 2026 month: 11 day: 23) response: self response)
			with: (WodifyDay fromJSON: (JSON parse: '{"date": "2026-11-24", "title": "", "items": [], "note": "Not published yet"}')))
		ok: false error: 'connection closed by the server' loading: false today: '2026-11-23'.
	^card
! !

!WodifyTest methodsFor: 'tests'!
testPlainText
	self assert: (WodifyText plain: '<p>Hello&nbsp;<b>world</b></p><p>Next &amp; last&#8217;s &#x2014; end</p>') equals: 'Hello world
Next & last’s — end'.
	self assert: (WodifyText plain: '<ul><li>one</li><li class="x">two</li></ul>') equals: '• one
• two'.
	self assert: (WodifyText plain: 'a<br><br><br><br>b') equals: 'a

b'.
	self assert: (WodifyText plain: nil) equals: ''.
	self assert: (WodifyText plain: 42) equals: '42'.
	self assert: (WodifyText plain: 'x &bogus; y') equals: 'x &bogus; y'
!
testLevels
	| text |
	text := 'Intro
- RX -
21-15-9
- BEGINNER -
15-12-9'.
	self assert: (WodifyText level: '' of: text hiding: #('beginner')) equals: 'Intro
- RX -
21-15-9'.
	self assert: (WodifyText level: 'rx' of: text hiding: #()) equals: 'Intro

21-15-9'.
	self assert: (WodifyText level: 'masters' of: text hiding: #()) equals: text.
	self assert: (WodifyText level: '' of: 'no blocks' hiding: #('rx')) equals: 'no blocks'.
	self assert: (WodifyText squash: 'Warm-Up 2') equals: 'warmup2'.
	self assert: (WodifyText isHidden: 'Warm Up' by: #('warmup')).
	self deny: (WodifyText isHidden: 'Metcon' by: #('warmup'))
!
testApiVersion
	| script |
	script := 'x.callDataAction("DataActionGetAllWorkoutData", "0d9f6f0a-1b2c-4d5e-8f90-123456789abc", "screenservices/W/Get", "AbC_123-x", function() {});
		y.callServerAction("Do_Login", "screenservices/WodifyClient/ActionDo_Login", "v2Hash", {});'.
	self assert: (WodifyClient apiVersionOf: 'DataActionGetAllWorkoutData' endpoint: 'screenservices/W/Get' in: script) equals: 'AbC_123-x'.
	self assert: (WodifyClient apiVersionOf: 'Do_Login' endpoint: 'screenservices/WodifyClient/ActionDo_Login' in: script) equals: 'v2Hash'.
	self assert: (WodifyClient apiVersionOf: 'Prepare_Login' endpoint: 'x' in: script) isNil
!
testValues
	self assert: (WodifyClient isWodifyHost: 'mygym.wodify.com').
	self deny: (WodifyClient isWodifyHost: 'evil.com/x.wodify.com').
	self deny: (WodifyClient isWodifyHost: '.wodify.com').
	self assert: (WodifyClient hasId: '0012').
	self deny: (WodifyClient hasId: '000').
	self deny: (WodifyClient hasId: nil).
	self assert: (WodifyClient str: 42) equals: '42'.
	self assert: (WodifyClient list: (JSON parse: '{"List": [1, 2]}')) equals: #(1 2).
	self assert: (WodifyClient list: 'x') equals: #().
	self assert: (WodifyClient isoLocal: 1795984266) equals: '2026-11-29T20:31:06'.
	self assert: (WodifyClient percentDecode: 'a%3Bcrf%3DT6C%2B9i') equals: 'a;crf=T6C+9i'.
	self assert: (WodifyService keyOf: (JSON parse: '{"host": "G.wodify.com", "email": "A@b", "password": "secret"}')) equals: 'g.wodify.com|a@b|'.
	self assert: (WodifyClient errorOf: (JSON parse: '{"Error": {"HasError": true, "ErrorMessage": "Wrong password"}}')) equals: 'Wrong password'.
	self assert: (WodifyClient errorOf: (JSON parse: '{"Error": {"HasError": false}}')) equals: ''
!
testShapeDay
	| day items |
	day := WodifyDay date: (Date year: 2026 month: 11 day: 23) response: self response.
	self assert: day date equals: '2026-11-23'.
	self assert: day title equals: 'CrossFit - Mon, Nov 23'.
	self assert: day comments equals: 'Scale as needed'.
	self assert: day note equals: ''.
	items := day items.
	self assert: (items collect: [:i | i at: 'name']) equals: #('Warm Up' 'Row' 'Strength' 'Back Squat' 'Metcon').
	self assert: ((items at: 2) at: 'text') equals: '500m
easy'.
	self assert: ((items at: 4) at: 'text') equals: 'Every 2:00
5x5'.
	self assert: ((items at: 4) at: 'comment') equals: 'Build'.
	self assert: ((items first) at: 'section').
	"the cache round trip"
	day := WodifyDay fromJSON: (JSON parse: (JSON render: day asJSON)).
	self assert: (day items collect: [:i | i at: 'name']) equals: #('Warm Up' 'Row' 'Strength' 'Back Squat' 'Metcon').
	self assert: (WodifyDay fromJSON: 'x') isNil.
	self assert: (WodifyDay date: (Date year: 2026 month: 11 day: 24) response: Dictionary new) note equals: 'Not published yet'
!
testCard
	| card canvas |
	card := self cardWithDays.
	self assert: (card shownDays collect: [:d | d date]) equals: #('2026-11-23' '2026-11-24').
	self assert: ((card visibleItems: card shownDays first items) collect: [:i | i at: 'name']) equals: #('Strength' 'Back Squat' 'Metcon').
	self assert: (card dayLabel: '2026-11-23') equals: 'TODAY'.
	self assert: (card dayLabel: '2026-11-24') equals: 'TOMORROW'.
	self assert: (card dayLabel: '2026-11-26') equals: 'THURSDAY'.
	self assert: (card dateLabel: '2026-11-23') equals: 'Mon 23 Nov'.
	self assert: (card levelText: '- RX -
21-15-9
- BEGINNER -
15-12-9') equals: '- RX -
21-15-9'.
	card settings: (JSON parse: '{"days": 1}').
	self assert: card shownDays size equals: 1.
	card maxHeight: 120.
	self assert: card preferredExtent y equals: 120.
	self assert: card maxScroll > 0.
	card bounds: (0 @ 0 extent: card preferredExtent).
	canvas := Canvas extent: card preferredExtent scale: 1.
	card drawOn: canvas.
	card scrollOffset: 1.0e9.
	self assert: card scrollOffset equals: card maxScroll
!
testStatus
	| card |
	card := WodifyCard new.
	self assert: card statusText equals: 'Fetching workouts…'.
	card days: #() ok: false error: 'login: Wrong password' loading: false today: '2026-11-23'.
	self assert: card statusText equals: 'login: Wrong password'.
	self assert: card preferredExtent y > 0
! !
