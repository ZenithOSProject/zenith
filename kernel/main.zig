const builtin = @import("builtin");
const options = @import("options");

pub const arch = @field(@import("arch.zig"), @tagName(builtin.target.cpu.arch));
pub const platform = if (@hasDecl(arch.platforms, options.platform)) @field(arch.platforms, options.platform) else struct {};

comptime {
    _ = arch;
    _ = platform;
}

pub fn main() void {}
