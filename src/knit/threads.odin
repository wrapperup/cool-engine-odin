package knit

import "core:thread"
import "core:sys/windows"

thread_lock_to_core :: proc(t: ^thread.Thread, core_index: uint) {
    when ODIN_OS == .Windows {
        windows.SetThreadAffinityMask(t.specific.win32_thread, 1 << core_index)
    } else {
        // TODO: Implement for other operating systems
        unreachable()
    }
}
