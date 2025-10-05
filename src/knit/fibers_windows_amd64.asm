; ASM for setting/getting/swapping context
; Adapted from https://graphitemaster.github.io/fibers/

bits 64

global get_fiber_context
global set_fiber_context
global swap_fiber_context

section .text
; FiberContext layout
;   0x00: rip (8)   8*0
;   0x08: rsp (8)   8*1
;   0x10: rbx (8)   8*2
;   0x18: rbp (8)   8*3
;   0x20: r12 (8)   8*4
;   0x28: r13 (8)   8*5
;   0x30: r14 (8)   8*6
;   0x38: r15 (8)   8*7
;   0x40: rdi (8)   8*8
;   0x48: rsi (8)   8*9
;   0x50: xmm6..15  10 * 16 bytes starting at 8*10

; get_fiber_context :: proc(ctx: ^FiberContext)
get_fiber_context:
    ; Save rip and rsp
    mov     r8, [rsp]
    mov     [rcx + 8*0], r8
    lea     r8, [rsp + 8]
    mov     [rcx + 8*1], r8

    ; Save registers
    mov     [rcx + 8*2], rbx
    mov     [rcx + 8*3], rbp
    mov     [rcx + 8*4], r12
    mov     [rcx + 8*5], r13
    mov     [rcx + 8*6], r14
    mov     [rcx + 8*7], r15
    mov     [rcx + 8*8], rdi
    mov     [rcx + 8*9], rsi

    ; Windows specific: Save xmm registers
    movups  [rcx + 8*10 + 16*0], xmm6
    movups  [rcx + 8*10 + 16*1], xmm7
    movups  [rcx + 8*10 + 16*2], xmm8
    movups  [rcx + 8*10 + 16*3], xmm9
    movups  [rcx + 8*10 + 16*4], xmm10
    movups  [rcx + 8*10 + 16*5], xmm11
    movups  [rcx + 8*10 + 16*6], xmm12
    movups  [rcx + 8*10 + 16*7], xmm13
    movups  [rcx + 8*10 + 16*8], xmm14
    movups  [rcx + 8*10 + 16*9], xmm15

    ; return 0
    xor     eax, eax
    ret

; set_fiber_context :: proc(ctx: ^FiberContext)
set_fiber_context:
    ; Restore rip and rsp
    mov     r8,  [rcx + 8*0]
    mov     rsp, [rcx + 8*1]

    ; Restore registers
    mov     rbx, [rcx + 8*2]
    mov     rbp, [rcx + 8*3]
    mov     r12, [rcx + 8*4]
    mov     r13, [rcx + 8*5]
    mov     r14, [rcx + 8*6]
    mov     r15, [rcx + 8*7]
    mov     rdi, [rcx + 8*8]
    mov     rsi, [rcx + 8*9]

    ; Windows specific: Restore xmm registers
    movups  xmm6,  [rcx + 8*10 + 16*0]
    movups  xmm7,  [rcx + 8*10 + 16*1]
    movups  xmm8,  [rcx + 8*10 + 16*2]
    movups  xmm9,  [rcx + 8*10 + 16*3]
    movups  xmm10, [rcx + 8*10 + 16*4]
    movups  xmm11, [rcx + 8*10 + 16*5]
    movups  xmm12, [rcx + 8*10 + 16*6]
    movups  xmm13, [rcx + 8*10 + 16*7]
    movups  xmm14, [rcx + 8*10 + 16*8]
    movups  xmm15, [rcx + 8*10 + 16*9]

    push    r8
    ret

; swap_fiber_context :: proc(old: ^FiberContext, new: ^FiberContext)
; combination of get_fiber_context and set_fiber_context in-place
swap_fiber_context:
    ; Saving context to old
    ; Save rip and rsp
    mov     r8, [rsp]
    mov     [rcx + 8*0], r8
    lea     r8, [rsp + 8]
    mov     [rcx + 8*1], r8

    ; Save registers
    mov     [rcx + 8*2], rbx
    mov     [rcx + 8*3], rbp
    mov     [rcx + 8*4], r12
    mov     [rcx + 8*5], r13
    mov     [rcx + 8*6], r14
    mov     [rcx + 8*7], r15
    mov     [rcx + 8*8], rdi
    mov     [rcx + 8*9], rsi

    ; Windows specific: Save xmm registers
    movups  [rcx + 8*10 + 16*0], xmm6
    movups  [rcx + 8*10 + 16*1], xmm7
    movups  [rcx + 8*10 + 16*2], xmm8
    movups  [rcx + 8*10 + 16*3], xmm9
    movups  [rcx + 8*10 + 16*4], xmm10
    movups  [rcx + 8*10 + 16*5], xmm11
    movups  [rcx + 8*10 + 16*6], xmm12
    movups  [rcx + 8*10 + 16*7], xmm13
    movups  [rcx + 8*10 + 16*8], xmm14
    movups  [rcx + 8*10 + 16*9], xmm15

    ; Setting context to new
    ; Restore rip and rsp
    mov     r8,  [rdx + 8*0]
    mov     rsp, [rdx + 8*1]

    ; Restore registers
    mov     rbx, [rdx + 8*2]
    mov     rbp, [rdx + 8*3]
    mov     r12, [rdx + 8*4]
    mov     r13, [rdx + 8*5]
    mov     r14, [rdx + 8*6]
    mov     r15, [rdx + 8*7]
    mov     rdi, [rdx + 8*8]
    mov     rsi, [rdx + 8*9]

    ; Windows specific: Restore xmm registers
    movups  xmm6,  [rdx + 8*10 + 16*0]
    movups  xmm7,  [rdx + 8*10 + 16*1]
    movups  xmm8,  [rdx + 8*10 + 16*2]
    movups  xmm9,  [rdx + 8*10 + 16*3]
    movups  xmm10, [rdx + 8*10 + 16*4]
    movups  xmm11, [rdx + 8*10 + 16*5]
    movups  xmm12, [rdx + 8*10 + 16*6]
    movups  xmm13, [rdx + 8*10 + 16*7]
    movups  xmm14, [rdx + 8*10 + 16*8]
    movups  xmm15, [rdx + 8*10 + 16*9]

    push    r8
    ret
