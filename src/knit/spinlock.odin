package knit

import "base:intrinsics"
SpinLock :: struct {
    locked: bool
}

spin_lock :: proc(spinlock: ^SpinLock) {
    for intrinsics.atomic_exchange(&spinlock.locked, true) {}
}

spin_unlock :: proc(spinlock: ^SpinLock) {
    intrinsics.atomic_store(&spinlock.locked, false)
}
