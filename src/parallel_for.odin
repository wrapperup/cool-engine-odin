package game

import "base:runtime"
import "deps:knit"

TASK_COUNT :: 12
LAST_TASK_INDEX :: TASK_COUNT - 1

Parallel_For_Procedure :: proc(index: int, data: rawptr = nil)

Parallel_For_Task_Data :: struct {
	data:          rawptr,
	procedure:     Parallel_For_Procedure,
	iter_per_task: int,
	allocator:     runtime.Allocator,
	offset:        int,
}

parallel_for_proc :: proc(data: ^Parallel_For_Task_Data) {
	for i in 0 ..< data.iter_per_task {
		data.procedure(i + data.offset, data.data)
	}
}

parallel_for_impl :: proc(length: int, procedure: Parallel_For_Procedure, data: rawptr = nil, allocator := context.allocator) {
	iter_per_task := length / TASK_COUNT
	remainder := length % TASK_COUNT

	tasks: [TASK_COUNT]knit.TaskDecl
	tasks_data: [TASK_COUNT]Parallel_For_Task_Data

	// Not even
	if remainder > 0 {
		for i in 0 ..< TASK_COUNT - 1 {
			tasks_data[i] = {
				data          = data,
				procedure     = procedure,
				iter_per_task = iter_per_task,
				allocator     = allocator,
				offset        = i * iter_per_task,
			}
			tasks[i] = knit.task(parallel_for_proc, &tasks_data[i])
		}
		tasks_data[LAST_TASK_INDEX] = {
			data          = data,
			procedure     = procedure,
			iter_per_task = remainder,
			allocator     = allocator,
			offset        = (LAST_TASK_INDEX) * iter_per_task,
		}
		tasks[LAST_TASK_INDEX] = knit.task(parallel_for_proc, &tasks_data[TASK_COUNT - 1])
	} else {
		for i in 0 ..< TASK_COUNT {
			tasks_data[i] = {
				data          = data,
				procedure     = procedure,
				iter_per_task = iter_per_task,
				allocator     = allocator,
				offset        = i * iter_per_task,
			}
			tasks[i] = knit.task(parallel_for_proc, &tasks_data[i])
		}
	}

	knit.wait(knit.run_tasks(tasks[:]))
}

parallel_for_typed :: proc(length: int, procedure: Parallel_For_Procedure, data: ^$T = nil, allocator := context.allocator) {
    parallel_for_impl(length, procedure, cast(rawptr)data, allocator)
}

parallel_for :: proc {
    parallel_for_impl,
    parallel_for_typed,
}
