package knit

import "base:intrinsics"
import "core:math/rand"
import "core:mem"
import "core:testing"
import "core:thread"
import "core:time"

// Power-of-two ring buffer with owner-only growth.
RingBuffer :: struct($T: typeid) {
	buf: []T,
}

// Make with power-of-two capacity
ring_make :: proc($T: typeid, cap_pow2: int) -> RingBuffer(T) {
	assert(cap_pow2 > 0 && (cap_pow2 & (cap_pow2 - 1)) == 0, "Cap must be power of 2")
	rb := RingBuffer(T) {
		buf = make([]T, cap_pow2),
	}
	return rb
}

ring_free :: proc(rb: ^RingBuffer($T)) {
	if rb.buf != nil {
		delete(rb.buf)
		rb.buf = nil
	}
}

ring_idx :: proc(rb: ^RingBuffer($T), logical: int) -> int {
	return logical % len(rb.buf)
}

ring_set :: proc(rb: ^RingBuffer($T), logical: int, v: T) {
	rb.buf[ring_idx(rb, logical)] = v
}

ring_get :: proc(rb: ^RingBuffer($T), logical: int) -> T {
	return rb.buf[ring_idx(rb, logical)]
}

// Double capacity. Call ONLY from the deque owner while thieves
// cannot observe inconsistent state (Chase–Lev owner path).
ring_grow_double :: proc(rb: ^RingBuffer($T), top: int, bottom: int) {
	old_cap := len(rb.buf)
	new_cap := old_cap << 1
	new_buf := make([]T, new_cap)

	// Copy active window [top .. bottom)
	for i := top; i < bottom; i += 1 {
		new_buf[i & (new_cap - 1)] = rb.buf[i & (old_cap - 1)]
	}

	delete(rb.buf)
	rb.buf = new_buf
}


//////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////


Deque :: struct($T: typeid) {
	ring:           RingBuffer(T),
	top:            int, // atomic
	bottom:         int, // owner-only
}

deque_init :: proc(d: ^Deque($T), initial_cap_pow2: int) {
	d.ring = ring_make(T, initial_cap_pow2)
	d.top = 0
	d.bottom = 0
}

deque_free :: proc(d: ^Deque($T)) {
	ring_free(&d.ring)
}

deque_is_empty :: proc(d: ^Deque($T)) -> bool {
	assert(d.ring.buf != nil, "Deque is not initialized")

	b := d.bottom
	t := intrinsics.atomic_load_explicit(&d.top, .Acquire)

	return t == b
}

// Owner push (bottom). Returns false only if grow fails (bounded build).
deque_push_bottom :: proc(d: ^Deque($T), v: T, initial_cap_pow2 := 32) -> bool {
	assert(d.ring.buf != nil, "Deque is not initialized")

	b := d.bottom
	t := intrinsics.atomic_load_explicit(&d.top, .Acquire)
	if (b - t) >= len(d.ring.buf) {
		// grow owner-only
		ring_grow_double(&d.ring, t, b)
	}
	ring_set(&d.ring, b, v)
	// publish by advancing bottom last
	d.bottom = b + 1
	return true
}

// Owner pop (bottom). Returns true if got one.
deque_pop_bottom :: proc(d: ^Deque($T)) -> (T, bool) {
	assert(d.ring.buf != nil, "Deque is not initialized")

	b := d.bottom - 1
	d.bottom = b
	t := intrinsics.atomic_load_explicit(&d.top, .Acquire)

	if t <= b {
		v := ring_get(&d.ring, b)
		if t == b {
			// single-item race
			if _, ok := intrinsics.atomic_compare_exchange_weak_explicit(
				&d.top,
				t,
				t + 1,
				.Acq_Rel,
				.Acquire,
			); ok {
				d.bottom = t + 1
				return v, true
			} else {
				// stolen
				d.bottom = t + 1
				return {}, false
			}
		} else {
			return v, true
		}
	} else {
		// empty; restore bottom to observed top
		d.bottom = t
		return {}, false
	}
}

// Thief steal (top). Returns true if got one.
deque_steal_top :: proc(d: ^Deque($T)) -> (T, bool) {
	assert(d.ring.buf != nil, "Deque is not initialized")

	for {
		t := intrinsics.atomic_load_explicit(&d.top, .Acquire)
		b := intrinsics.atomic_load_explicit(&d.bottom, .Acquire) // benign race
		if t >= b {
			return {}, false // empty
		}
		v := ring_get(&d.ring, t)
		if _, ok := intrinsics.atomic_compare_exchange_weak_explicit(
			&d.top,
			t,
			t + 1,
			.Acq_Rel,
			.Acquire,
		); ok {
			return v, true
		}
	}
}

@(test)
stress_deque_with_threads :: proc(t: ^testing.T) {
	TestingStruct :: struct {
		a: u32,
		b: bool,
	}

	TestDeque :: Deque(TestingStruct)
	deque: TestDeque
	deque_init(&deque, 8192)

	for i in 0 ..< 5000 {
		deque_push_bottom(&deque, TestingStruct{a = rand.uint32()})
	}

	thread_pool: thread.Pool
	thread.pool_init(&thread_pool, context.allocator, 10)

	stealer_proc :: proc(task: thread.Task) {
		deque := cast(^TestDeque)task.data
		for i in 0 ..< 100 {
			value, ok := deque_steal_top(deque)
			assert(ok)
		}
	}

	producer_proc :: proc(task: thread.Task) {
		deque := cast(^TestDeque)task.data
		for i in 0 ..< 100 {
			ok := deque_push_bottom(deque, TestingStruct{a = rand.uint32()})
			assert(ok)
		}
	}

	// Producer thread
	thread.pool_add_task(&thread_pool, context.allocator, producer_proc, &deque)

	for i in 1 ..= 10 {
		thread.pool_add_task(&thread_pool, context.allocator, stealer_proc, &deque, i)
	}

	thread.pool_start(&thread_pool)
	thread.pool_finish(&thread_pool)
	thread.pool_destroy(&thread_pool)
}
