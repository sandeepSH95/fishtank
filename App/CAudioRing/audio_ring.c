#include "audio_ring.h"

#include <stdatomic.h>
#include <stdlib.h>

struct audio_ring {
    float *data;
    size_t mask;
    _Atomic size_t head;
    _Atomic size_t tail;
};

audio_ring *audio_ring_create(size_t capacity_floats)
{
    size_t cap = 1;
    while (cap < capacity_floats)
        cap <<= 1;

    audio_ring *ring = calloc(1, sizeof *ring);
    if (!ring)
        return NULL;
    ring->data = calloc(cap, sizeof(float));
    if (!ring->data) {
        free(ring);
        return NULL;
    }
    ring->mask = cap - 1;
    return ring;
}

void audio_ring_destroy(audio_ring *ring)
{
    if (!ring)
        return;
    free(ring->data);
    free(ring);
}

size_t audio_ring_write(audio_ring *ring, const float *samples, size_t count)
{
    size_t head = atomic_load_explicit(&ring->head, memory_order_relaxed);
    size_t tail = atomic_load_explicit(&ring->tail, memory_order_acquire);
    size_t space = ring->mask + 1 - (head - tail);
    if (count > space)
        count = space;
    for (size_t i = 0; i < count; i++)
        ring->data[(head + i) & ring->mask] = samples[i];
    atomic_store_explicit(&ring->head, head + count, memory_order_release);
    return count;
}

size_t audio_ring_read(audio_ring *ring, float *out, size_t count)
{
    size_t tail = atomic_load_explicit(&ring->tail, memory_order_relaxed);
    size_t head = atomic_load_explicit(&ring->head, memory_order_acquire);
    size_t avail = head - tail;
    if (count > avail)
        count = avail;
    for (size_t i = 0; i < count; i++)
        out[i] = ring->data[(tail + i) & ring->mask];
    atomic_store_explicit(&ring->tail, tail + count, memory_order_release);
    return count;
}
