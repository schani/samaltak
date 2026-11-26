"""Instrument the archived VM C for diagnosis; the exact binary runs first."""
from pathlib import Path
import re

for name in ("opt_runtime", "jit_runtime"):
    path = Path(f"vm/gen/{name}.c")
    s = path.read_text()
    s = re.sub(r"\b(bg_(?:invalidate|quiesce))\(\);",
               r'bg_lifecycle_trace("\1", __func__); \1();', s)
    if name == "jit_runtime":
        s = s.replace('#include "samaltak.h"', '#include "samaltak.h"\nvoid bg_lifecycle_trace(const char *, const char *);')
    else:
        s = s.replace('static void bg_complete(void);', r'''
void bg_lifecycle_trace(const char *event, const char *caller)
{
    if (!rt_bg_owned)
        return;
    fprintf(stderr, "BG %s %s key=%08llx stale=%d hold=%d scavenge=%llu full=%llu flush=%llu\n",
            event, caller, (unsigned long long)(rt_bg_key >> 32), rt_bg_stale,
            rt_bg_test_hold, (unsigned long long)stat_scavenges,
            (unsigned long long)stat_full_gcs, (unsigned long long)stat_cache_flushes);
}
static void bg_complete(void);''')
        s = s.replace('    rt_bg_state = 1;\n', '    bg_lifecycle_trace("queue", __func__);\n    rt_bg_state = 1;\n')
        s = s.replace('    bg_note_discard();\n    bg_reset();',
                      '    bg_lifecycle_trace("discard", __func__);\n    bg_note_discard();\n    bg_reset();')
        s = s.replace('    if (rt_bg_stale || (flush_pending || (!rt_bg_ok))) {',
                      '    bg_lifecycle_trace("complete", __func__);\n'
                      '    if (rt_bg_stale || (flush_pending || (!rt_bg_ok))) {')
        s = s.replace('    if (cmd == 4) {', r'''    if (cmd != 4 && ((jit_flags & JIT_FLAG_BG) != 0)) {
        fprintf(stderr, "BG cmd=%d outcome=%d owned=%d method=", cmd, rt_bg_test_outcome, rt_bg_owned);
        print_activation(m, nil_oop, nil_oop, stderr);
    }
    if (cmd == 4) {''')
        s = s.replace('    if (rt_bg_owned) {\n        bg_lifecycle_trace("bg_quiesce", __func__); bg_quiesce();',
                      r'''    if (rt_bg_owned) {
        fprintf(stderr, "BG competing compile start=%d osr=%d method=", rt_unit_start, rt_unit_osr);
        print_activation(m, nil_oop, nil_oop, stderr);
        bg_lifecycle_trace("bg_quiesce", __func__); bg_quiesce();''')
    path.write_text(s)
