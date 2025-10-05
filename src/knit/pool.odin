package knit

import "base:intrinsics"
import "core:math/rand"
import "core:testing"
import "core:thread"
import "core:time"

PoolState :: enum u8 {
	Free,
	InUse,
}
#assert(size_of(PoolState) == 1)

PoolHeadIndex :: bit_field u64 {
	index: int | 32,
	gen:   u32 | 32,
}

Pool :: struct($N: int, $T: typeid) {
	nodes:          [N]T,
	next:           [N]int,
	head:           PoolHeadIndex, // atomic
	state:          [N]PoolState,
	is_initialized: bool,
}

pool_init :: proc(p: ^Pool($N, $T)) {
	p.head.index = 0
	p.head.gen = 0

	for i in 0 ..< len(p.next) - 1 {
		p.next[i] = int(i + 1)
	}

	p.next[len(p.next) - 1] = -1
	p.is_initialized = true
}

pool_destroy :: proc(p: ^Pool($N, $T)) {
	p.is_initialized = false
}

pool_pop :: proc(p: ^Pool($N, $T), keep_uninitialized := false) -> (^T, int, bool) {
	assert(p.is_initialized, "Pool is not initialized")

	for {
		old_head := intrinsics.atomic_load_explicit(&p.head, .Acquire)
		if old_head.index < 0 {
			return nil, -1, false
		}

		new_head_index := p.next[old_head.index]
		new_head: PoolHeadIndex
		new_head.index = new_head_index
		new_head.gen = old_head.gen + 1

		if value, ok := intrinsics.atomic_compare_exchange_weak(&p.head, old_head, new_head); ok {
			if !keep_uninitialized {
				p.nodes[old_head.index] = {}
			}
			p.state[old_head.index] = .InUse
			return &p.nodes[old_head.index], old_head.index, true
		}
	}
}

pool_release :: proc(p: ^Pool($N, $T), index: int) {
	assert(p.is_initialized, "Pool is not initialized")
	assert(p.state[index] == .InUse, "Double free")

	p.state[index] = .Free

	for {
		old_head := intrinsics.atomic_load(&p.head)
		p.next[index] = old_head.index

		new_head: PoolHeadIndex
		new_head.index = index
		new_head.gen = old_head.gen + 1

		if value, ok := intrinsics.atomic_compare_exchange_weak(&p.head, old_head, new_head); ok {
			return
		}
	}
}

pool_get :: proc(p: ^Pool($N, $T), index: int) -> ^T {
	assert(p.is_initialized, "Pool is not initialized")
	return &p.nodes[index]
}

@(test)
stress_pool_with_threads :: proc(t: ^testing.T) {
	TestingStruct :: struct {
		a: u32,
		b: bool,
	}

	test: Pool(16, TestingStruct)
	pool_init(&test)

	thread_pool: thread.Pool
	thread.pool_init(&thread_pool, context.allocator, 10)

	worker_proc :: proc(task: thread.Task) {
		test := cast(^Pool(16, TestingStruct))task.data
		for i in 0 ..< 100_000 {
			_, a_handle, a_ok := pool_pop(test)
			if a_ok {
				time.sleep(time.Duration(rand.int63() % 100))
				pool_release(test, a_handle)
			}
		}
	}

	for i in 0 ..< 10 {
		thread.pool_add_task(&thread_pool, context.allocator, worker_proc, &test)
	}

	thread.pool_start(&thread_pool)
	thread.pool_finish(&thread_pool)
	thread.pool_destroy(&thread_pool)
}
