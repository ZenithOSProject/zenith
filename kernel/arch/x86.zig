pub const Gdt = @import("x86/Gdt.zig");

pub const io = @import("x86/io.zig");
pub const platforms = @import("x86/platforms.zig");

pub fn bootstrap() void {
    Gdt.init();
}
