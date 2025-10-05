package knit

import "core:os"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:thread"

@(private, thread_local)
_worker_index: int

TaskId :: int
Task :: struct {
	using decl: TaskDecl,
	wait_group:    WaitGroupId,
}

Worker :: struct {
	init_fiber_context: FiberContext,
	task_to_start:      Task,
	current_fiber:      FiberId,
	release_fiber:      FiberId,
	ready_fibers:       Deque(FiberId),
}

WaitGroupId :: int
WaitGroup :: struct {
	count:              int, // atomic
	waiting_fiber_head: int,
}

requeue_waiting_fibers :: proc(wait_group: ^WaitGroup) {
	head := intrinsics.atomic_exchange_explicit(&wait_group.waiting_fiber_head, -1, .Acq_Rel)
	i := head
	for i != -1 {
		n := pool_get(&_scheduler.waiting_fibers, i)
		next := n.next // store raw next when using NIL scheme

		deque_push_bottom(&get_worker().ready_fibers, n.fiber)
		pool_release(&_scheduler.waiting_fibers, i)

		i = next
	}
}

WaitingFiber :: struct {
	fiber: FiberId,
	next:  int,
}

TaskScheduler :: struct {
	fibers:          Pool(160, Fiber),
	waiting_fibers:  Pool(160, WaitingFiber),
	wait_groups:        Pool(1024, WaitGroup),
	task_lock:       SpinLock, // TODO: Swap to lock-free MPMC queue, or queue per thread (+worksteal)
	task_queue:      Deque(Task), // TODO: This is not thread-safe when dealing with threads producing tasks.
	workers:         []Worker,
	threads:         []^thread.Thread,
	num_outstanding: int,
	is_running:      bool,
}

TaskDecl :: struct {
	procedure: proc(data: rawptr),
	data:      rawptr,
}

_scheduler: TaskScheduler

thread_worker_proc :: proc(t: ^thread.Thread) {
	_worker_index = t.user_index
	for intrinsics.atomic_load(&_scheduler.is_running) {
		if intrinsics.atomic_load(&_scheduler.num_outstanding) > 0 {
			swap_to_next_ready_fiber(in_worker_thread = true)
		}
	}
}

init :: proc(thread_num: int = 0) {
    thread_num := thread_num
    assert(thread_num <= os.processor_core_count())

    if thread_num == 0 {
        thread_num = os.processor_core_count()
    }

	pool_init(&_scheduler.fibers)
	pool_init(&_scheduler.waiting_fibers)
	pool_init(&_scheduler.wait_groups)
	deque_init(&_scheduler.task_queue, 128)
	_scheduler.num_outstanding = 0
	_scheduler.is_running = true

	_scheduler.workers = make([]Worker, thread_num)
	for &worker in _scheduler.workers {
		worker.current_fiber = -1
		deque_init(&worker.ready_fibers, 128)
	}

	// -1 because the main thread is included.
	_scheduler.threads = make([]^thread.Thread, thread_num - 1)
	for &t, i in _scheduler.threads {
		t = thread.create(thread_worker_proc)
		t.user_index = i + 1
        thread_lock_to_core(t, uint(i + 1))
		thread.start(t)
	}

	// Main thread gets index 0 always.
	_worker_index = 0
}

destroy :: proc() {
	// Free allocated stacks in each Fiber
	intrinsics.atomic_store(&_scheduler.is_running, false)

	for &t, i in _scheduler.threads {
		thread.destroy(t)
	}

	for &fiber in _scheduler.fibers.nodes {
		if fiber.stack != nil {
			free(fiber.stack)
		}
	}

	delete(_scheduler.workers)
	delete(_scheduler.threads)

	deque_free(&_scheduler.task_queue)
}

get_worker :: proc() -> ^Worker {
	return &_scheduler.workers[_worker_index]
}

task_typed :: proc(procedure: proc(_: ^$T), data: ^T = nil) -> TaskDecl {
	return {cast(proc(_: rawptr))procedure, cast(rawptr)data}
}

task_raw :: proc(procedure: proc(_: rawptr), data: rawptr = nil) -> TaskDecl {
	return {procedure, data}
}

task :: proc {
	task_typed,
	task_raw,
}

run_tasks :: proc(decls: []TaskDecl) -> WaitGroupId {
	wait_group, wait_group_id, wait_group_ok := pool_pop(&_scheduler.wait_groups)
	wait_group.waiting_fiber_head = -1
	intrinsics.atomic_store_explicit(&wait_group.count, 0, .Release)
	assert(wait_group_ok)

	for decl in decls {
		task := Task {
			decl    = decl,
			wait_group = wait_group_id,
		}

        spin_lock(&_scheduler.task_lock)
		deque_push_bottom(&_scheduler.task_queue, task)
        spin_unlock(&_scheduler.task_lock)
	}

	// Increment wait_group.
	intrinsics.atomic_add_explicit(&wait_group.count, len(decls), .Acq_Rel)

	// Increment task wait_group
	intrinsics.atomic_add(&_scheduler.num_outstanding, len(decls))

	return wait_group_id
}

wait :: proc(id: WaitGroupId) {
	c := pool_get(&_scheduler.wait_groups, id)

	// Fast path
	if intrinsics.atomic_load_explicit(&c.count, .Acquire) == 0 {
		return
	}

	// Only fibers park
	if get_worker().current_fiber == -1 {
		for intrinsics.atomic_load_explicit(&c.count, .Acquire) > 0 {
			swap_to_next_ready_fiber(release_old_fiber = false)
			cleanup_released_fiber()
		}
		return
	}

	// Add our fiber to the waiting list for this wait_group.
	{
		node, idx, ok := pool_pop(&_scheduler.waiting_fibers)
		assert(ok)
		node.fiber = get_worker().current_fiber
		node.next = -1
		for {
			old_head := intrinsics.atomic_load_explicit(&c.waiting_fiber_head, .Acquire)
			node.next = old_head
			_, ok := intrinsics.atomic_compare_exchange_weak_explicit(
				&c.waiting_fiber_head,
				old_head,
				idx,
				.Acq_Rel,
				.Acquire,
			)
			if ok {
				break
			}
		}

		// Check if the wait_group decremented while we were detaching
		if intrinsics.atomic_load_explicit(&c.count, .Acquire) == 0 {
			head := intrinsics.atomic_exchange_explicit(&c.waiting_fiber_head, -1, .Acq_Rel)
			i := head
			for i != -1 {
				n := &_scheduler.waiting_fibers.nodes[i]
				next := n.next
				deque_push_bottom(&get_worker().ready_fibers, n.fiber)
				pool_release(&_scheduler.waiting_fibers, i)
				i = next
			}
			return
		}
	}

	assert(get_worker().release_fiber != get_worker().current_fiber)

	swap_to_next_ready_fiber(release_old_fiber = false)
	cleanup_released_fiber()
}

cleanup_released_fiber :: proc() {
	worker := get_worker()
	if worker.release_fiber != -1 {
		pool_release(&_scheduler.fibers, worker.release_fiber)
		worker.release_fiber = -1
	}
}

swap_to_next_ready_fiber :: proc(release_old_fiber := false, in_worker_thread := false) {
	if release_old_fiber {
		get_worker().release_fiber = get_worker().current_fiber
	} else {
		get_worker().release_fiber = -1
	}

	// 1) Ready fibers first
	if !deque_is_empty(&get_worker().ready_fibers) {
		new_id, ok := deque_pop_bottom(&get_worker().ready_fibers)
		assert(ok)
		new_fiber := pool_get(&_scheduler.fibers, new_id)

		was_from_init := get_worker().current_fiber == -1
		if !was_from_init {
			old := pool_get(&_scheduler.fibers, get_worker().current_fiber)
			get_worker().current_fiber = new_id
			swap_fiber_context(&old.ctx, &new_fiber.ctx)
		} else {
			get_worker().current_fiber = new_id
			swap_fiber_context(&get_worker().init_fiber_context, &new_fiber.ctx)
		}
		return
	}

	// 2) No ready fibers; try to admit a task
    spin_lock(&_scheduler.task_lock)
	task, task_ok := deque_pop_bottom(&_scheduler.task_queue);
    spin_unlock(&_scheduler.task_lock)
	if task_ok {
		new_fiber, new_id, got := pool_pop(&_scheduler.fibers, keep_uninitialized = true)
		assert(got, "Increase fiber pool")

		if new_fiber.stack == nil {
			stack, err := mem.alloc_bytes(128 * 64 * 1024)
			assert(err == .None)
			new_fiber.stack = cast(^u8)raw_data(stack)
		}

		new_fiber.ctx = make_fiber_context(_worker_entry, new_fiber.stack, 128 * 64 * 1024)
		get_worker().task_to_start = task

		was_from_init := get_worker().current_fiber == -1
		if !was_from_init {
			old := pool_get(&_scheduler.fibers, get_worker().current_fiber)
			get_worker().current_fiber = new_id
			swap_fiber_context(&old.ctx, &new_fiber.ctx)
		} else {
			get_worker().current_fiber = new_id
			swap_fiber_context(&get_worker().init_fiber_context, &new_fiber.ctx)
		}
		return
	}

	// 3) Try stealing a ready task from another get_worker() TODO

	// 4) Nothing to run
	if get_worker().current_fiber != -1 {
		old := pool_get(&_scheduler.fibers, get_worker().current_fiber)
		get_worker().current_fiber = -1
		swap_fiber_context(&old.ctx, &get_worker().init_fiber_context)
	}
}

_worker_entry :: proc "contextless" () {
	context = runtime.default_context()

	cleanup_released_fiber()

	worker := get_worker()
	task := get_worker().task_to_start
	task.procedure(task.data)

	if task.wait_group != -1 {
		wait_group := pool_get(&_scheduler.wait_groups, task.wait_group)
		old_count := intrinsics.atomic_sub(&wait_group.count, 1)
		if old_count <= 1 {
			requeue_waiting_fibers(wait_group)
		}
	}

	// Decrement task count
	old_count := intrinsics.atomic_sub(&_scheduler.num_outstanding, 1)
	assert(old_count > 0, "Task count went negative. This shouldn't happen.")

	swap_to_next_ready_fiber(release_old_fiber = true)
}
