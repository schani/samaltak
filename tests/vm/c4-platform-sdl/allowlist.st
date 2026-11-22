| check names actual path try |
check := [:ok :why | ok ifFalse: [
    Smalltalk vm stderrWrite: why, (String with: Character lf).
    Smalltalk quit: 1]].
names := Smalltalk vm primitiveNames.
actual := OrderedCollection new.
400 to: (699 min: names size) do: [:i |
    (#(567 568 569 570 572 573 574 575 576 577 578) includes: i) ifFalse: [
        (names at: i) ifNotNil: [:n | actual add: n]]].
check value: actual asArray = #(
    'windowOpen' 'windowClose' 'windowSize' 'windowPixelSize' 'windowDisplayScale'
    'nextEvent' 'inputSemaphore' 'platformLastError' 'windowPresentRGBA'
    'fileOpen' 'fileClose' 'fileRead' 'fileWrite' 'fileSize' 'filePosition'
    'fileSeek' 'fileFlush' 'fileDelete' 'fileRename' 'fileStat' 'dirEntries' 'dirCreate' 'cwd')
    value: 'wrong platform reflection allowlist'.
try := [:id :args | thisContext tryPrimitive: id receiver: Smalltalk vm args: args].
#('baseline' 'opt' 'none') do: [:mode |
    check value: (try value: 180 value: {{mode. '-prims'. 0. 0}}) == #primitiveFailed
        value: 'image changed JIT parameters'].
path := Smalltalk vm getenv: 'C4_SDL_DENIED'.
File class compile: 'c4SDLTestMkfifo: path
    <primitive: 514>
    ^#denied'.
check value: (File c4SDLTestMkfifo: path) == #denied value: 'compiled primitive ran mkfifo'.
check value: (try value: 514 value: {path}) == #primitiveFailed value: 'tryPrimitive ran mkfifo'.
check value: (File exists: path) not value: 'mkfifo side effect'.
check value: (try value: 400 value: {16. 16. 'must not open'. 0}) == #primitiveFailed
    value: 'headless opened a window'.
check value: (try value: 421 value: {1. 1. 1. #[1 2 3 4]}) == #primitiveFailed
    value: 'headless presented'.
check value: (try value: 414 value: {(1 bitShift: 32) + 1}) == #primitiveFailed
    value: 'semaphore index narrowed'.
Smalltalk vm stdoutWrite: 'C4 SDL allowlist ok', (String with: Character lf).
Smalltalk quit: 0
