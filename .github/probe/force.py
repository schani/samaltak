# CI probe, not for merging: hold AgentConversation>>ask:images: for 30 ms (running, so that it is preempted)
# between its two state changes: after the message is in the items (before the fix), after it is busy (after).
import sys

path, variant = sys.argv[1], sys.argv[2]
hold = "\t[:t | [Time millisecondClockValue < t] whileTrue] value: Time millisecondClockValue + 30.\n"
source = open(path).read()
if variant == "before":
    anchor = "\titems add: (AgentItem user: aString images: images).\n"
    assert anchor in source
    source = source.replace(anchor, anchor + hold, 1)
else:
    anchor = "\tself add: message.\n"
    assert anchor in source
    source = source.replace(anchor, hold + anchor, 1)
open(path, "w").write(source)
