pub const Gdt = @import("x86/Gdt.zig");
pub const Idt = @import("x86/Idt.zig");
pub const Irq = @import("x86/Irq.zig");
pub const isr = @import("x86/isr.zig");
pub const paging = @import("x86/paging.zig");

pub const io = @import("x86/io.zig");
pub const platforms = @import("x86/platforms.zig");

pub fn bootstrap() void {
    Gdt.init();
    Idt.init();
    isr.init();
    Irq.init();
}
