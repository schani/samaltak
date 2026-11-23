TestCase subclass: #ByteSearchTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

ByteSearchTest comment: 'ByteSearch, run as Smalltalk (VMSimulation) with the blocks of each CPU (both run here), answers what a naive search answers and reads nothing outside the bytes it searches: each lies in simulated memory with nothing mapped after it.'!

!ByteSearchTest methodsFor: 'running'!
timeLimitMilliseconds
	^120000
! !

!ByteSearchTest methodsFor: 'helpers'!
withPointerTo: aByteArray in: aSimulation do: aBlock
	| memory address |
	memory := aSimulation memory.
	address := memory allocate: aByteArray size.
	^[
		memory bytesAt: address put: aByteArray.
		aBlock value: (memory pointerTo: (CTypeRegistry default at: 'uint8_t') at: address)
	] ensure: [memory free: address]
!
naiveIndexOf: needle in: haystack from: start
	start to: haystack size - needle size do: [:i |
		(haystack copyFrom: i + 1 to: i + needle size) = needle ifTrue: [^i]].
	^-1
!
searchWith: aBlocksClass
	"Haystacks around the block sizes, alphabets of 1, 2 and 3 bytes (many partial matches; 254, 255 and 0) and of all 256; needles cut from the haystack at a random place and at its end, the same with a middle byte changed (the first and the last still match), and random ones; starts from 0 to past the last position."
	| sim search random |
	sim := VMSimulation modules: {ByteSearch. aBlocksClass}.
	search := sim module: ByteSearch.
	random := Random seed: 1234.
	#(0 1 2 7 8 9 15 16 17 18 23 24 31 32 33 40 47 48 49 70) do: [:n |
		#(1 2 3 256) do: [:k |
			| haystack |
			haystack := ((1 to: n) collect: [:i | 253 + (random nextInt: k) \\ 256]) asByteArray.
			self withPointerTo: haystack in: sim do: [:a |
				((#(1 2 3 8 9 16 17 19 20) , {n - 1. n. n + 1}) select: [:m | m between: 1 and: n + 1]) asSet do: [:m |
					| last needles |
					last := n - m.
					needles := OrderedCollection with: ((1 to: m) collect: [:i | 253 + (random nextInt: k) \\ 256]) asByteArray.
					m <= n ifTrue: [
						{random nextInt: last + 1. last + 1} do: [:o |
							| needle j |
							needle := haystack copyFrom: o to: o + m - 1.
							needles add: needle.
							m > 2 ifTrue: [
								needle := needle copy.
								j := random between: 2 and: m - 1.
								needle at: j put: (needle at: j) + 1 \\ 256.
								needles add: needle]]].
					needles do: [:needle |
						self withPointerTo: needle in: sim do: [:b |
							({0. 1. random nextInt: n + 1. last. last + 1. n + 1} select: [:s | s >= 0]) asSet do: [:s |
								self
									assert: (search indexOfBytes: b size: m in: a size: n from: s)
									equals: (self naiveIndexOf: needle in: haystack from: s)].
							m = 1 ifTrue: [
								{0. 1. last. last + 1. n} do: [:s |
									s >= 0 ifTrue: [
										self
											assert: (search indexOfByte: needle first in: a size: n from: s)
											equals: (self naiveIndexOf: needle in: haystack from: s)]]]]]]]]]
! !

!ByteSearchTest methodsFor: 'tests'!
testSse2Blocks
	self searchWith: Sse2ByteBlocks
!
testSwarBlocks
	self searchWith: SwarByteBlocks
! !
