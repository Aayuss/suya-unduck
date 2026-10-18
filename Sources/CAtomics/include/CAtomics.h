#ifndef CATOMICS_H
#define CATOMICS_H
#include <stdint.h>

/// Opaque to Swift (imported as OpaquePointer). All access goes through these functions.
typedef struct AMShared AMShared;

AMShared *am_shared_create(float initial_gain);
void      am_shared_destroy(AMShared *s);

void      am_set_target_gain(AMShared *s, float g);   // control thread
float     am_get_target_gain(AMShared *s);            // RT thread
void      am_store_peak(AMShared *s, float p);        // RT thread: plain atomic store of THIS buffer's peak
float     am_load_peak(AMShared *s);                  // UI thread: sample at 15 Hz; meter decays visually
void      am_inc_callbacks(AMShared *s);              // RT thread
uint64_t  am_get_callbacks(AMShared *s);              // watchdog
void      am_inc_format_errors(AMShared *s);          // RT thread
uint64_t  am_get_format_errors(AMShared *s);          // watchdog
void      am_set_failed(AMShared *s);                 // RT thread: one-way flag "stop using me"
int       am_is_failed(AMShared *s);                  // watchdog (250 ms) → destroy pipeline
void      am_inject_fault(AMShared *s);               // lab/test only: next callback treats layout as mismatched
int       am_take_fault(AMShared *s);                 // RT thread: read + clear the injected fault
int       am_atomics_are_lock_free(void);             // self-test: must return 1
// First three callback shapes, recorded without allocation. index 0..149.
void am_probe_store(AMShared *s, uint32_t index, uint32_t value);
uint32_t am_probe_load(AMShared *s, uint32_t index);

#endif
