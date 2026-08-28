#ifndef AUDIO_RING_H
#define AUDIO_RING_H

#include <stddef.h>

// Single-producer single-consumer lock-free ring buffer of floats.
// write() is safe to call from a real-time audio thread.
// On overflow the newest samples are dropped; the consumer is expected to
// drain fully each cycle, so the ring never fills in normal operation.

typedef struct audio_ring audio_ring;

audio_ring *audio_ring_create(size_t capacity_floats);
void audio_ring_destroy(audio_ring *ring);
size_t audio_ring_write(audio_ring *ring, const float *samples, size_t count);
size_t audio_ring_read(audio_ring *ring, float *out, size_t count);

#endif
