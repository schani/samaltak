| check event next weak keep sem index stats legacy |
check := [:ok :why | ok ifFalse: [
    Smalltalk vm stderrWrite: why, (String with: Character lf).
    Smalltalk quit: 1]].
legacy := (Smalltalk vm getenv: 'C4_SDL_LEGACY') notNil.
legacy ifTrue: [
    | names |
    names := Smalltalk vm primitiveNames.
    check value: ((names at: 421) = 'windowSetSize' and: [(names at: 422) isNil])
        value: 'legacy resize aliases the C4 SDL presentation primitive'].
event := Array new: 8.
next := [:target | thisContext tryPrimitive: 412 receiver: Smalltalk vm args: {target}].
sem := Semaphore new.
index := Smalltalk vm registerExternalSemaphore: sem.
check value: (thisContext tryPrimitive: 414 receiver: Smalltalk vm args: {index}) == Smalltalk vm
    value: 'cannot register input semaphore'.
weak := WeakArray new: 1.
weak at: 1 put: (ByteArray new: 2097153).
keep := Array new: 40.
1 to: 36 do: [:i |
    ByteArray new: 1048583.
    1 to: 800 do: [:j | keep at: j \\ 40 + 1 put: i @ j].
    (Delay forMilliseconds: 5) wait].
legacy ifTrue: [Smalltalk vm garbageCollect].
(Delay forMilliseconds: 150) wait.
check value: ((keep at: 1) = (36 @ 800)) value: 'lost live Points'.
check value: (weak at: 1) isNil value: 'deferred work did not span a collection'.
check value: sem excessSignals = 1 value: 'input notification is not edge/rearm driven'.
check value: (next value: (Array new: 7)) == #primitiveFailed value: 'short event carrier accepted'.
check value: ((next value: event) == event and: [event first = 10 and: [(event at: 8) isNil]])
    value: 'SDL quit adaptation failed'.
check value: ((next value: event) == event and: [event first = 7 and: [event second = 53
    and: [(event at: 7) = ('copied ', (String with: (Character value: 955)))]]])
    value: 'deferred native text not copied/decoded'.
check value: ((next value: event) == event and: [event first = 4 and: [event second = 54
    and: [(event at: 3) = 42.5 and: [(event at: 4) = 13.25 and: [(event at: 7) = (-2.5 @ 3.25)]]]]])
    value: 'deferred wheel Point failed'.
check value: (next value: event) isNil value: 'queue not drained'.
check value: (thisContext tryPrimitive: 414 receiver: Smalltalk vm args: {0}) == Smalltalk vm
    value: 'cannot unregister input semaphore'.
Smalltalk vm unregisterExternalSemaphore: index.
stats := Smalltalk vm primStatistics.
legacy not
    ifTrue: [
        check value: (stats first = 0 and: [stats second = 0 and: [(stats at: 15) = 0 and: [(stats at: 20) = 0]]])
            value: 'legacy collections or JIT in C4 SDL']
    ifFalse: [check value: stats first + stats second > 0 value: 'no legacy collection'].
Smalltalk vm stdoutWrite: 'SDL event contract ok', (String with: Character lf).
Smalltalk quit: 0
