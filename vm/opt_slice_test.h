#ifndef OPT_SLICE_TEST_H
#define OPT_SLICE_TEST_H

#if defined(SAMALTAK_OPT_SLICE_TEST)
# if !defined(__linux__) || !defined(__x86_64__) || !defined(SAMALTAK_NO_PLATFORM) || \
     defined(SAMALTAK_UEFI) || defined(SAMALTAK_C4_PLATFORM_FILES) || \
     defined(SAMALTAK_C4_PLATFORM_SDL) || defined(SAMALTAK_C4_ARM64_INTERPRETER)
#  error "SAMALTAK_OPT_SLICE_TEST requires the Linux x86-64 headless test build"
# endif
# define OPT_SLICE_TEST_ENABLED 1
#else
# define OPT_SLICE_TEST_ENABLED 0
#endif

#endif
