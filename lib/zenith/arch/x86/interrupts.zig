const Idt = @import("Idt.zig");
const Cpu = @import("Cpu.zig");
const Irq = @import("Irq.zig");
const Gdt = @import("Gdt.zig");
const isr = @import("isr.zig");

fn handler(state: *Cpu.State) callconv(.C) usize {
    if (state.int_num < Irq.OFFSET) {
        return isr.handler(state);
    } else {
        return Irq.handler(state);
    }
}

fn commonStub() callconv(.Naked) void {
    asm volatile (
        \\pusha
        \\push  %%ds
        \\push  %%es
        \\push  %%fs
        \\push  %%gs
        \\mov %%cr3, %%eax
        \\push %%eax
        \\mov   $0x10, %%ax
        \\mov   %%ax, %%ds
        \\mov   %%ax, %%es
        \\mov   %%ax, %%fs
        \\mov   %%ax, %%gs
        \\mov   %%esp, %%eax
        \\push  %%eax
        \\call  %[handler:P]
        \\mov   %%eax, %%esp
        \\pop   %%eax
        \\mov   %%cr3, %%ebx
        \\cmp   %%eax, %%ebx
        \\je    same_cr3
        \\mov   %%eax, %%cr3
        \\same_cr3:
        \\pop   %%gs
        \\pop   %%fs
        \\pop   %%es
        \\pop   %%ds
        \\popa
        \\add   $0x1C, %%esp
        \\mov   %%esp, %[main_tss_entry]
        \\sub   $0x14, %%esp
        \\iret
        :
        : [handler] "X" (&handler),
          [main_tss_entry] "R" (&Gdt.main_tss_entry),
    );
}

pub fn getStub(comptime i: u32) Idt.Handler {
    return (struct {
        fn func() callconv(.Naked) void {
            asm volatile ("cli");

            if (i != 8 and !(i >= 10 and i <= 14) and i != 17) {
                asm volatile ("pushl $0");
            }

            asm volatile (
                \\ pushl %[nr]
                \\ jmp %[commonStub:P]
                :
                : [nr] "n" (i),
                  [commonStub] "X" (&commonStub),
            );
        }
    }).func;
}
