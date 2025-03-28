const mem = @import("../mem.zig");

pub const Gdt = @import("x86/Gdt.zig");
pub const Idt = @import("x86/Idt.zig");
pub const Irq = @import("x86/Irq.zig");
pub const isr = @import("x86/isr.zig");
pub const paging = @import("x86/paging.zig");

pub const io = @import("x86/io.zig");
pub const platforms = @import("x86/platforms.zig");

pub const VmmPayload = *paging.Directory;
pub const KERNEL_VMM_PAYLOAD = &paging.kernel_directory;
pub const MEMORY_BLOCK_SIZE: usize = paging.PAGE_SIZE_4KB;
pub const VMM_MAPPER = mem.virt.Mapper(VmmPayload){ .mapFn = paging.map, .unmapFn = paging.unmap };

pub fn bootstrap() void {
    Gdt.init();
    Idt.init();
    isr.init();
    Irq.init();
}
