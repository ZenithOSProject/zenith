const builtin = @import("builtin");

pub const Bitmap = @import("zenith/bitmap.zig").Bitmap;

pub const arch = @import("zenith/arch.zig");
pub const boot = @import("zenith/boot.zig");
pub const mem = @import("zenith/mem.zig");

test {
    _ = @field(arch, @tagName(builtin.cpu.arch));
    _ = Bitmap;
    _ = boot;
    _ = mem;
}
