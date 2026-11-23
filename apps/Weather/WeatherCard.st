OmarchyCard subclass: #WeatherCard
	instanceVariableNames: 'report location error imperial'
	classVariableNames: ''
	package: 'Weather'!

WeatherCard comment: 'I show the weather as the Omarchy desktop card and the bar''s weather panel do: the current conditions (the weather''s glyph, the temperature large, the place and FEELS, WIND, HUMID) above a hairline and the next three days (glyph, day, high and low), an OmarchyCard. Until the first report I say what is going on.

A click runs onActivate (the app opens the bar''s weather panel), a middle click onRefresh.'!

!WeatherCard methodsFor: 'initialization'!
initialize
	super initialize.
	error := ''.
	imperial := false
! !

!WeatherCard methodsFor: 'accessing'!
report: aReport location: aLocation error: aString
	"Show what the service has now (any Process: my window's do: runs me)."
	report := aReport.
	location := aLocation.
	error := aString ifNil: [''].
	self invalidate
!
report
	^report
!
imperial: aBoolean
	imperial := aBoolean.
	self invalidate
!
statusText
	"What I show without a report."
	^error isEmpty ifTrue: ['Fetching weather…'] ifFalse: [error]
! !

!WeatherCard methodsFor: 'fonts'!
iconFont
	^self fontOfSize: 64 bold: false
!
temperatureFont
	^self fontOfSize: 56 bold: true
!
unitFont
	^self fontOfSize: (self pixelsOf: #display) bold: false
!
placeFont
	^self fontOfSize: (self pixelsOf: #body) bold: false tracking: 1
!
markerFont
	^self fontOfSize: (self pixelsOf: #body) bold: false
!
statLabelFont
	^self fontOfSize: (self pixelsOf: #bodySmall) bold: false tracking: 1
!
statValueFont
	^self fontOfSize: (self pixelsOf: #title) bold: false
!
dayIconFont
	^self fontOfSize: (self pixelsOf: #display) bold: false
!
dayNameFont
	^self fontOfSize: (self pixelsOf: #caption) bold: false tracking: 1
!
dayTemperatureFont
	^self fontOfSize: (self pixelsOf: #body) bold: false
!
statusFont
	^self fontOfSize: (self pixelsOf: #bodySmall) bold: false
! !

!WeatherCard methodsFor: 'layout'!
heroHeight
	^self heroLeftHeight max: self heroRightHeight
!
heroLeftHeight
	^self iconFont lineHeight max: self temperatureFont lineHeight
!
heroRightHeight
	^self placeFont lineHeight + (self space: 12) + self statHeight
!
statHeight
	^self statLabelFont lineHeight + (self space: 5) + self statValueFont lineHeight
!
forecastHeight
	^self dayIconFont lineHeight max: self dayNameFont lineHeight + (self space: 2) + self dayTemperatureFont lineHeight
!
contentHeight
	^self heroHeight + (self space: 14) + (self space: 1) + (self space: 14) + self forecastHeight
! !

!WeatherCard methodsFor: 'drawing'!
drawContentOn: aCanvas width: w
	report isNil ifTrue: [
		^aCanvas drawString: self statusText at: 0 @ 0 font: self statusFont color: self dimmer].
	self drawHeroOn: aCanvas.
	aCanvas fillRect: (0 @ (self heroHeight + (self space: 14)) extent: w @ (self space: 1))
		color: (self foreground alpha: 0.12).
	aCanvas translateBy: 0 @ (self heroHeight + (2 * (self space: 14)) + (self space: 1)) during: [
		self drawForecastOn: aCanvas width: w]
!
drawHeroOn: c
	"Left: the glyph and the temperature, vertically centered; right: the place above the stats."
	| h x iconFont tempFont unitFont temp tempY rightX y stats w |
	h := self heroHeight.
	iconFont := self iconFont.
	tempFont := self temperatureFont.
	unitFont := self unitFont.
	x := self space: 16.
	c drawString: report icon at: x @ ((h - iconFont lineHeight) / 2 + 5) font: iconFont color: self foreground.
	x := x + (self widthOf: report icon in: iconFont) + (self space: 16).
	temp := WeatherReport temperature: report temperature imperial: imperial.
	tempY := (h - tempFont lineHeight) / 2.
	c drawString: temp at: x @ tempY font: tempFont color: self foreground.
	x := x + (self widthOf: temp in: tempFont) + (self space: 2).
	c drawString: self unitText at: x @ (tempY + (self space: 10)) font: unitFont color: self foreground.
	stats := self stats.
	w := self statsWidth: stats.
	rightX := self width - (2 * self cardPadding) - (self space: 20) - w.
	y := (h - self heroRightHeight) / 2.
	self drawPlaceOn: c at: rightX @ y width: w.
	y := y + self placeFont lineHeight + (self space: 12).
	stats do: [:pair |
		c drawString: pair first at: rightX @ y font: self statLabelFont color: self dimmer.
		c drawString: pair last at: rightX @ (y + self statLabelFont lineHeight + (self space: 5)) font: self statValueFont color: self foreground.
		rightX := rightX + (self statWidth: pair) + (self space: 36)]
!
drawPlaceOn: c at: aPoint width: w
	| marker name font x |
	location isNil ifTrue: [^self].
	location name isEmpty ifTrue: [^self].
	marker := WeatherIcons mapMarker.
	font := self placeFont.
	c drawString: marker at: aPoint font: self markerFont color: self dim.
	x := aPoint x + (self widthOf: marker in: self markerFont) + (self space: 6).
	name := self truncate: location name asUppercase to: w - (x - aPoint x) font: font.
	c drawString: name at: x @ aPoint y font: font color: self dim
!
drawForecastOn: c width: width
	"Each day: its glyph beside its name and its high and low; the days centered."
	| days cells x |
	days := report days.
	days isEmpty ifTrue: [^self].
	cells := days collect: [:day | self cellWidthOf: day].
	x := (width - ((cells inject: 0 into: [:a :b | a + b]) + ((days size - 1) * (self space: 44)))) / 2.
	days with: cells do: [:day :cellWidth |
		self drawDay: day on: c at: x.
		x := x + cellWidth + (self space: 44)]
!
drawDay: aDay on: c at: left
	| h iconFont nameFont tempFont x y high low |
	h := self forecastHeight.
	iconFont := self dayIconFont.
	nameFont := self dayNameFont.
	tempFont := self dayTemperatureFont.
	c drawString: aDay icon at: left @ ((h - iconFont lineHeight) / 2) font: iconFont color: self foreground.
	x := left + (self widthOf: aDay icon in: iconFont) + (self space: 10).
	y := (h - (nameFont lineHeight + (self space: 2) + tempFont lineHeight)) / 2.
	c drawString: aDay dayName asUppercase at: x @ y font: nameFont color: self dim.
	y := y + nameFont lineHeight + (self space: 2).
	high := self degrees: aDay high.
	low := self degrees: aDay low.
	c drawString: high at: x @ y font: tempFont color: self foreground.
	c drawString: low at: (x + (self widthOf: high in: tempFont) + (self space: 6)) @ y font: tempFont color: self dimmer
!
cellWidthOf: aDay
	| tempFont temps |
	tempFont := self dayTemperatureFont.
	temps := (self widthOf: (self degrees: aDay high) in: tempFont) + (self space: 6) + (self widthOf: (self degrees: aDay low) in: tempFont).
	^(self widthOf: aDay icon in: self dayIconFont) + (self space: 10) + ((self widthOf: aDay dayName asUppercase in: self dayNameFont) max: temps)
!
stats
	"{label. value} for FEELS, WIND and HUMID."
	^Array
		with: (Array with: 'FEELS' with: (self degrees: report feelsLike), (imperial ifTrue: ['F'] ifFalse: ['C']))
		with: (Array with: 'WIND' with: (WeatherReport wind: report wind imperial: imperial))
		with: (Array with: 'HUMID' with: (report humidity isNil ifTrue: [''] ifFalse: [(WeatherReport round: report humidity) printString, '%']))
!
statWidth: aPair
	^(self widthOf: aPair first in: self statLabelFont) max: (self widthOf: aPair last in: self statValueFont)
!
statsWidth: stats
	^(stats inject: 0 into: [:sum :each | sum + (self statWidth: each)]) + ((stats size - 1) * (self space: 36))
!
degrees: celsius
	| n |
	n := WeatherReport temperature: celsius imperial: imperial.
	^n isEmpty ifTrue: [''] ifFalse: [n, '°']
!
unitText
	^'°', (imperial ifTrue: ['F'] ifFalse: ['C'])
! !

!WeatherCard methodsFor: 'remote control'!
remoteLabel
	report isNil ifTrue: [^self statusText].
	^(WeatherReport temperature: report temperature imperial: imperial), self unitText
!
remoteState
	report isNil ifTrue: [^#('fetching')].
	^Array
		with: 'place=', (location isNil ifTrue: [''] ifFalse: [location name])
		with: 'days=', (report days collect: [:d | d dayName]) printString
! !
