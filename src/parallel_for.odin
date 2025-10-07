package game

import "base:runtime"
import "deps:knit"

TASK_COUNT :: 12

Parallel_For_Procedure :: proc(index: int, data: rawptr = nil)

Parallel_For_Data :: struct {
	data:          rawptr,
	procedure:     Parallel_For_Procedure,
	iter_per_task: int,
	remainder:     int,
}

Parallel_For_Task_Data :: struct {
    data:          rawptr,
    procedure:     Parallel_For_Procedure,
    iter_per_task: int,
    remainder:     int,
    allocator:     runtime.Allocator,
    offset:        int,
}


parallel_for_proc :: proc(data: ^Parallel_For_Task_Data) {
	for i in 0 ..< data.iter_per_task {
		data.procedure(i + data.offset, data.data)
	}
}

parallel_for_proc_rem :: proc(data: ^Parallel_For_Task_Data) {
	for i in 0 ..< data.remainder {
		data.procedure(i + data.offset, data.data)
	}
}

parallel_for :: proc(length: int, procedure: Parallel_For_Procedure, data: rawptr = nil, allocator := context.allocator) {
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
				remainder     = remainder,
				allocator     = allocator,
				offset        = i * iter_per_task,
			}
			procedure_to_use := i == TASK_COUNT - 1 ? parallel_for_proc_rem : parallel_for_proc
			tasks[i] = knit.task(procedure_to_use, &tasks_data[i])
		}
	} else {
		for i in 0 ..< TASK_COUNT {
			tasks_data[i] = {
				data          = data,
				procedure     = procedure,
				iter_per_task = iter_per_task,
				remainder     = remainder,
				allocator = allocator,
				offset    = i * iter_per_task,
			}
			tasks[i] = knit.task(parallel_for_proc, &tasks_data[i])
		}
	}

	knit.wait(knit.run_tasks(tasks[:]))
}
