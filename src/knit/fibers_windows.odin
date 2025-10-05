#+build windows
package knit

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:thread"
import "core:time"

when ODIN_ARCH == .amd64 {
    foreign import fiber_helpers "fibers_windows_amd64.asm"
} else {
    #assert(false, "Only Windows x64 is supported.")
}

@(default_calling_convention = "c")
foreign fiber_helpers {
	// Stores the current context into c
	get_fiber_context :: proc(c: ^FiberContext) ---

	// Sets the context to c
	set_fiber_context :: proc(c: ^FiberContext) ---

	// Stores the current context into old, and sets the context to new.
	swap_fiber_context :: proc(old: ^FiberContext, new: ^FiberContext) ---
}

when ODIN_OS == .Windows {
	when ODIN_ARCH == .amd64 {
		FiberContext :: struct {
			rip, rsp:                          rawptr,
			rbx, rbp, r12, r13:                rawptr,
			r14, r15, rdi, rsi:                rawptr,

			// WINDOWS ABI ONLY
			xmm6, xmm7, xmm8, xmm9, xmm10:     [2]u64,
			xmm11, xmm12, xmm13, xmm14, xmm15: [2]u64,
		}
	}
}

FiberId :: int
Fiber :: struct {
	ctx:   FiberContext,
	stack: ^u8,
}

make_fiber_context :: proc(
	proc_ptr: proc "contextless" (),
	stack_ptr: ^u8,
	stack_len: int,
) -> FiberContext {
	sp := mem.ptr_offset(stack_ptr, stack_len)

	// Align stack pointer on 16-byte boundary.
	sp = cast(^u8)mem.align_backward(sp, 16)

    // Reserve shadow space
	sp = mem.ptr_offset(sp, -32)

    // Reserve return address space
	sp = mem.ptr_offset(sp, -8)

	c: FiberContext
	c.rip = cast(rawptr)proc_ptr
	c.rsp = sp

	return c
}

check_ctx :: #force_inline proc(c: ^FiberContext) {
	// stack pointer should be 16-aligned after subtracting 8 (call pushes ret)
	assert((uintptr(c.rsp) & 15) == 0 || ((uintptr(c.rsp) - 8) & 15) == 0, "Unaligned RSP")
}
