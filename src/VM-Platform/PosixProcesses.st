CLibrary subclass: #PosixProcesses
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PosixProcesses comment: 'Child processes and pseudo-terminals: posix_spawnp, waitpid, kill, forkpty and what the forked child calls before execve; execvp. Not simulated. IUTF8 (not POSIX) is 0 where termios.h lacks it.'!

!PosixProcesses class methodsFor: 'declaring'!
headers
	"forkpty is declared in util.h on macOS, in pty.h on Linux."
	^#('<spawn.h>' '<sys/wait.h>' '<signal.h>' '<sys/ioctl.h>' '#ifdef __APPLE__' '<util.h>' '#else' '<pty.h>' '#endif' '<unistd.h>'
		'<termios.h>' '#ifndef IUTF8' '#define IUTF8 0' '#endif')
!
typedefs
	^#((posix_spawn_file_actions_t opaque) (posix_spawnattr_t opaque) (sigset_t uint32_t) (tcflag_t uint64_t))
! !

!PosixProcesses methodsFor: 'simulation'!
notSimulated
	^self error: 'processes are not simulated'
! !

!PosixProcesses methodsFor: 'processes'!
spawnp: pid file: file fileActions: fileActions attributes: attributes argv: argv envp: envp
	<c: 'int posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *file_actions, const posix_spawnattr_t *attributes, char **argv, char **envp)'>
	^self notSimulated
!
waitpid: pid status: status options: options
	<c: 'pid_t waitpid(pid_t pid, int *status, int options)'>
	^self notSimulated
!
WIFEXITED: status
	<c: 'bool WIFEXITED(int status)'>
	^self notSimulated
!
WEXITSTATUS: status
	<c: 'int WEXITSTATUS(int status)'>
	^self notSimulated
!
WTERMSIG: status
	<c: 'int WTERMSIG(int status)'>
	^self notSimulated
!
WNOHANG
	<cMacro: 'int WNOHANG'>
	^1
!
kill: pid signal: sig
	<c: 'int kill(pid_t pid, int sig)'>
	^self notSimulated
!
SIGHUP
	<cMacro: 'int SIGHUP'>
	^1
!
SIGINT
	<cMacro: 'int SIGINT'>
	^2
!
SIGTERM
	<cMacro: 'int SIGTERM'>
	^15
!
SA_SIGINFO
	<cMacro: 'int SA_SIGINFO'>
	^4
! !

!PosixProcesses methodsFor: 'pseudo-terminals'!
tcgetpgrp: fd
	<c: 'pid_t tcgetpgrp(int fd)'>
	^self notSimulated
!
forkpty: amaster name: name termios: termp winsize: winp
	<c: 'pid_t forkpty(int *amaster, char *name, struct termios *termp, struct winsize *winp)'>
	^self notSimulated
!
ioctl: fd request: request argument: argument
	<c: 'int ioctl(int fd, unsigned long request, ...)'>
	^self notSimulated
!
TIOCSWINSZ
	<cMacro: 'unsigned long TIOCSWINSZ'>
	^self notSimulated
!
getdtablesize
	<c: 'int getdtablesize(void)'>
	^self notSimulated
! !

!PosixProcesses methodsFor: 'the forked child'!
tcgetattr: fd termios: t
	<c: 'int tcgetattr(int fd, struct termios *t)'>
	^self notSimulated
!
tcsetattr: fd action: action termios: t
	<c: 'int tcsetattr(int fd, int optional_actions, const struct termios *t)'>
	^self notSimulated
!
TCSANOW
	<cMacro: 'int TCSANOW'>
	^0
!
IUTF8
	<cMacro: 'tcflag_t IUTF8'>
	^16r4000
!
sigaction: sig action: act old: oact
	<c: 'int sigaction(int sig, const struct sigaction *act, struct sigaction *oact)'>
	^self notSimulated
!
sigemptyset: set
	<c: 'int sigemptyset(sigset_t *set)'>
	^self notSimulated
!
sigprocmask: how set: set old: oset
	<c: 'int sigprocmask(int how, const sigset_t *set, sigset_t *oset)'>
	^self notSimulated
!
chdir: path
	<c: 'int chdir(const char *path)'>
	^self notSimulated
!
execve: path argv: argv envp: envp
	<c: 'int execve(const char *path, char **argv, char **envp)'>
	^self notSimulated
!
execvp: file argv: argv
	<c: 'int execvp(const char *file, char **argv)'>
	^self notSimulated
!
exit: status
	<c: 'void _exit(int status)'>
	<noreturn>
	^self notSimulated
!
NSIG
	<cMacro: 'int NSIG'>
	^32
!
SIG_SETMASK
	<cMacro: 'int SIG_SETMASK'>
	^3
!
SIG_DFL
	<cMacro: 'sig_t SIG_DFL'>
	^FunctionPointer null
! !

ExternStruct subclass: #Sigaction
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!Sigaction class methodsFor: 'declaring'!
cName
	^'struct sigaction'
!
fields
	"sa_sigaction (with SA_SIGINFO): void (*)(int, siginfo_t *, void *)"
	^#((sa_handler sig_t) (sa_sigaction 'void *') (sa_mask sigset_t) (sa_flags int))
! !

ExternStruct subclass: #Siginfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!Siginfo class methodsFor: 'declaring'!
cName
	^'siginfo_t'
!
fields
	^#((si_signo int) (si_pid int))
! !

ExternStruct subclass: #Winsize
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!Winsize class methodsFor: 'declaring'!
cName
	^'struct winsize'
!
fields
	^#((ws_row 'unsigned short') (ws_col 'unsigned short') (ws_xpixel 'unsigned short') (ws_ypixel 'unsigned short'))
! !

ExternStruct subclass: #Termios
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!Termios class methodsFor: 'declaring'!
cName
	^'struct termios'
!
fields
	^#((c_iflag tcflag_t))
! !
