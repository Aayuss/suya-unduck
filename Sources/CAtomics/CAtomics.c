#include "CAtomics.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "32-bit atomics must be lock-free");
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "64-bit atomics must be lock-free");

struct AMShared {
    _Atomic uint32_t target_gain_bits;
    _Atomic uint32_t peak_bits;
    _Atomic uint64_t callbacks;
    _Atomic uint64_t format_errors;
    _Atomic uint32_t failed;
    _Atomic uint32_t inject_fault;
    _Atomic uint32_t probe[150];
};

static inline uint32_t f2u(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }
static inline float    u2f(uint32_t u) { float f; memcpy(&f, &u, 4); return f; }

AMShared *am_shared_create(float g) {
    AMShared *s = calloc(1, sizeof(AMShared));
    if (s) atomic_store(&s->target_gain_bits, f2u(g));
    return s;
}
void  am_shared_destroy(AMShared *s) { free(s); }
void  am_set_target_gain(AMShared *s, float g) { atomic_store_explicit(&s->target_gain_bits, f2u(g), memory_order_relaxed); }
float am_get_target_gain(AMShared *s) { return u2f(atomic_load_explicit(&s->target_gain_bits, memory_order_relaxed)); }
void  am_store_peak(AMShared *s, float p) { atomic_store_explicit(&s->peak_bits, f2u(p), memory_order_relaxed); } // no retry loop
float am_load_peak(AMShared *s) { return u2f(atomic_load_explicit(&s->peak_bits, memory_order_relaxed)); }
void  am_set_failed(AMShared *s) { atomic_store_explicit(&s->failed, 1, memory_order_release); }
int   am_is_failed(AMShared *s) { return (int)atomic_load_explicit(&s->failed, memory_order_acquire); }
void  am_inject_fault(AMShared *s) { atomic_store_explicit(&s->inject_fault, 1, memory_order_relaxed); }
int   am_take_fault(AMShared *s) { return (int)atomic_exchange_explicit(&s->inject_fault, 0, memory_order_relaxed); }
int   am_atomics_are_lock_free(void) {
    AMShared t; return atomic_is_lock_free(&t.target_gain_bits) && atomic_is_lock_free(&t.callbacks);
}
void  am_inc_callbacks(AMShared *s) { atomic_fetch_add_explicit(&s->callbacks, 1, memory_order_relaxed); }
uint64_t am_get_callbacks(AMShared *s) { return atomic_load_explicit(&s->callbacks, memory_order_relaxed); }
void  am_inc_format_errors(AMShared *s) { atomic_fetch_add_explicit(&s->format_errors, 1, memory_order_relaxed); }
uint64_t am_get_format_errors(AMShared *s) { return atomic_load_explicit(&s->format_errors, memory_order_relaxed); }

void am_probe_store(AMShared *s, uint32_t index, uint32_t value) { if(index < 150) atomic_store_explicit(&s->probe[index], value, memory_order_release); }
uint32_t am_probe_load(AMShared *s, uint32_t index) { return index < 150 ? atomic_load_explicit(&s->probe[index], memory_order_acquire) : 0; }
