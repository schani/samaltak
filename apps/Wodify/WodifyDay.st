Object subclass: #WodifyDay
	instanceVariableNames: 'date title comments notes items note'
	classVariableNames: ''
	package: 'Wodify'!

WodifyDay comment: 'I am one day''s workout as the card shows it, shaped from Wodify''s GetAllWorkoutData response (unknown fields ignored): its date (ISO), the workout''s title, comments (scaling options, coach notes) and notes (the class plan, for coaches), its parts in order (items: Dictionaries section, name, text, comment; a section is a header over the parts after it), and a note when there are none (Not published yet, No workout, or what Wodify said). I am also what the offline cache keeps (asJSON, fromJSON:).'!

!WodifyDay methodsFor: 'initialization'!
setDate: anISOString title: t comments: c notes: n items: anArray note: aString
	date := anISOString.
	title := t.
	comments := c.
	notes := n.
	items := anArray.
	note := aString
! !

!WodifyDay methodsFor: 'accessing'!
date
	"YYYY-MM-DD."
	^date
!
title
	^title
!
comments
	^comments
!
notes
	^notes
!
items
	^items
!
note
	^note
!
asJSON
	^Dictionary new
		at: 'date' put: date; at: 'title' put: title; at: 'comments' put: comments; at: 'notes' put: notes;
		at: 'items' put: items; at: 'note' put: note;
		yourself
! !

!WodifyDay methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a WodifyDay '; nextPutAll: date; space; print: items size
! !

!WodifyDay class methodsFor: 'instance creation'!
date: aDate response: aResponse
	"aDate's workout from Wodify's response."
	| workout items werr note plain |
	plain := [:x | WodifyText plain: x].
	workout := self workoutIn: aResponse.
	items := OrderedCollection new.
	(WodifyClient list: (workout at: 'WorkoutComponents' ifAbsent: [nil])) do: [:c |
		(c isKindOf: Dictionary) ifTrue: [
			| name text prefix |
			name := plain value: (c at: 'Name' ifAbsent: [nil]).
			text := plain value: (c at: 'Description' ifAbsent: [nil]).
			text isEmpty ifTrue: [text := plain value: (c at: 'MeasureRepScheme' ifAbsent: [nil])].
			prefix := plain value: (c at: 'PrefixText' ifAbsent: [nil]).
			(prefix notEmpty and: [(text beginsWith: prefix) not]) ifTrue: [
				text := (prefix, (String with: Character lf), text) trimBoth].
			(WodifyClient truthy: (c at: 'IsSection' ifAbsent: [nil]))
				ifTrue: [name notEmpty ifTrue: [items add: (self item: name text: '' comment: '' section: true)]]
				ifFalse: [
					(name notEmpty or: [text notEmpty]) ifTrue: [
						items add: (self item: name text: text comment: (plain value: (c at: 'Comment' ifAbsent: [nil])) section: false)]]]].
	note := ''.
	werr := WodifyClient dictionary: ((WodifyClient dictionary: (aResponse at: 'ResponseWOD' ifAbsent: [nil])) at: 'WorkoutError' ifAbsent: [nil]).
	items isEmpty ifTrue: [
		note := ((WodifyClient truthy: (werr at: 'HasError' ifAbsent: [nil])) and: [WodifyClient truthy: (werr at: 'ErrorMessage' ifAbsent: [nil])])
			ifTrue: [plain value: (werr at: 'ErrorMessage')]
			ifFalse: [
				(WodifyClient truthy: (aResponse at: 'ErrorMessage' ifAbsent: [nil]))
					ifTrue: [plain value: (aResponse at: 'ErrorMessage')]
					ifFalse: [
						((WodifyClient truthy: (workout at: 'EmptyOrNotPublished' ifAbsent: [nil])) or: [workout isEmpty])
							ifTrue: ['Not published yet']
							ifFalse: ['No workout']]]].
	^self new
		setDate: aDate printString
		title: (plain value: (workout at: 'Name' ifAbsent: [nil]))
		comments: (plain value: (workout at: 'Comments' ifAbsent: [nil]))
		notes: (plain value: (workout at: 'Notes' ifAbsent: [nil]))
		items: items asArray
		note: note
!
fromJSON: aDictionary
	"A day the offline cache kept; nil if it is not one."
	| str items |
	(aDictionary isKindOf: Dictionary) ifFalse: [^nil].
	str := [:k | | v | v := aDictionary at: k ifAbsent: ['']. v isString ifTrue: [v] ifFalse: ['']].
	(str value: 'date') size = 10 ifFalse: [^nil].
	items := aDictionary at: 'items' ifAbsent: [#()].
	items := (items isKindOf: Array) ifTrue: [items select: [:i | i isKindOf: Dictionary]] ifFalse: [#()].
	^self new
		setDate: (str value: 'date') title: (str value: 'title') comments: (str value: 'comments') notes: (str value: 'notes')
		items: (items collect: [:i |
			self item: (self string: (i at: 'name' ifAbsent: [nil])) text: (self string: (i at: 'text' ifAbsent: [nil]))
				comment: (self string: (i at: 'comment' ifAbsent: [nil])) section: (i at: 'section' ifAbsent: [false]) == true])
		note: (str value: 'note')
!
item: name text: text comment: comment section: aBoolean
	^Dictionary new
		at: 'section' put: aBoolean; at: 'name' put: name; at: 'text' put: text; at: 'comment' put: comment;
		yourself
!
string: anObject
	^anObject isString ifTrue: [anObject] ifFalse: ['']
!
workoutIn: aResponse
	"The workout in a response: where its parts are, else ResponseWOD's workout (an empty Dictionary if none)."
	| node |
	#(#('ResponseWOD' 'ResponseWorkout') #('ResponseWorkout' 'ResponseWorkoutActions')) do: [:path |
		node := aResponse.
		path do: [:key | node := (node isKindOf: Dictionary) ifTrue: [node at: key ifAbsent: [nil]] ifFalse: [nil]].
		((node isKindOf: Dictionary) and: [(WodifyClient list: (node at: 'WorkoutComponents' ifAbsent: [nil])) notEmpty])
			ifTrue: [^node]].
	node := (WodifyClient dictionary: (aResponse at: 'ResponseWOD' ifAbsent: [nil])) at: 'ResponseWorkout' ifAbsent: [nil].
	^(node isKindOf: Dictionary) ifTrue: [node] ifFalse: [Dictionary new]
! !
