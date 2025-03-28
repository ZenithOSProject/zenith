const builtin = @import("builtin");
const std = @import("std");
const options = @import("options");

pub const arch = @field(@import("arch.zig"), @tagName(builtin.target.cpu.arch));
pub const platform = if (@hasDecl(arch.platforms, options.platform)) @field(arch.platforms, options.platform) else struct {};

comptime {
    _ = arch;
    _ = platform;
}

pub const panic = if (@hasDecl(platform, "panic")) platform.panic else std.debug.FullPanic(std.debug.defaultPanic);

pub fn main() void {
    b();
}

pub fn b() void {
    std.debug.panicExtra(@frameAddress(), "Shuba", .{});
}
