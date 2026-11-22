| check try win size w h pixels paint event sem index moved stats ack again keep |
check := [:ok :why | ok ifFalse: [
    Smalltalk vm stderrWrite: why, ': ', (thisContext tryPrimitive: 415 receiver: Smalltalk vm args: #()),
        (String with: Character lf).
    Smalltalk quit: 1]].
try := [:id :args | thisContext tryPrimitive: id receiver: Smalltalk vm args: args].
check value: (try value: 400 value: {(1 bitShift: 32) + 128. 96. 'invalid'. 0}) == #primitiveFailed
    value: 'window extent narrowed'.
win := try value: 400 value: {128. 96. 'C4 SDL CI witness'. 0}.
check value: win isInteger value: 'open failed'.
check value: (try value: 402 value: {win}) = #(128 96) value: 'wrong point extent'.
check value: (try value: 401 value: {win + (1 bitShift: 32)}) == #primitiveFailed
    value: 'window token narrowed'.
size := try value: 403 value: {win}.
w := size first.
h := size second.
check value: (w = 128 and: [h = 96]) value: 'wrong pixel extent'.
check value: (try value: 421 value: {win. w. h. #[0 0 0 0]}) == #primitiveFailed
    value: 'short input accepted'.
pixels := ByteArray new: w * h * 4.
paint := [:red :green :blue |
    1 to: pixels size by: 4 do: [:i |
        pixels at: i put: red; at: i + 1 put: green; at: i + 2 put: blue; at: i + 3 put: 255].
    check value: (try value: 421 value: {win. w. h. pixels}) == Smalltalk vm value: 'present failed'].
event := Array new: 8.
sem := Semaphore new.
index := Smalltalk vm registerExternalSemaphore: sem.
check value: (try value: 414 value: {index}) == Smalltalk vm value: 'cannot arm input'.
paint value: 213 value: 37 value: 61.
Smalltalk vm stdoutWrite: 'C4 SDL ready', (String with: Character lf).
moved := false.
[moved] whileFalse: [
    sem wait.
    [(try value: 412 value: {event}) == event] whileTrue: [
        (event first = 1 and: [(event at: 8) = win and: [(event at: 3) = 61 and: [(event at: 4) = 39]]])
            ifTrue: [moved := true]]].
keep := Array new: 40.
1 to: 36 do: [:i |
    ByteArray new: 1048583.
    1 to: 2500 do: [:j | keep at: j \\ 40 + 1 put: i @ j].
    (Delay forMilliseconds: 5) wait].
check value: ((keep at: 21) = (36 @ 2500)) value: 'lost retained points'.
paint value: 42 value: 193 value: 79.
Smalltalk vm stdoutWrite: 'C4 SDL motion and repaint', (String with: Character lf).
ack := Smalltalk vm getenv: 'C4_SDL_ACK'.
[File exists: ack] whileFalse: [(Delay forMilliseconds: 10) wait].
try value: 414 value: {0}.
Smalltalk vm unregisterExternalSemaphore: index.
check value: (try value: 401 value: {win}) == Smalltalk vm value: 'window close failed'.
again := try value: 400 value: {8. 8. 'C4 SDL replacement'. 1}.
check value: (again isInteger and: [again ~= win]) value: 'window token recycled'.
check value: (try value: 421 value: {win. w. h. pixels}) == #primitiveFailed value: 'stale present succeeded'.
check value: (try value: 401 value: {again}) == Smalltalk vm value: 'replacement close failed'.
stats := Smalltalk vm primStatistics.
check value: (stats first = 0 and: [stats second = 0 and: [(stats at: 15) = 0 and: [(stats at: 20) = 0]]])
    value: 'legacy GC or JIT in interactive run'.
Smalltalk vm stdoutWrite: 'C4 SDL interactive ok', (String with: Character lf).
Smalltalk quit: 0
