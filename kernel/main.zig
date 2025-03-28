const builtin = @import("builtin");
const std = @import("std");
const build_options = @import("options");

pub const arch = @field(@import("arch.zig"), @tagName(builtin.target.cpu.arch));
pub const platform = if (@hasDecl(arch.platforms, build_options.platform)) @field(arch.platforms, build_options.platform) else struct {};

comptime {
    _ = arch;
    _ = platform;
}

pub const panic = if (@hasDecl(platform, "panic")) platform.panic else std.debug.FullPanic(std.debug.defaultPanic);

pub const std_options: std.Options = .{
    .logFn = if (@hasDecl(platform, "logFn")) platform.logFn else std.log.defaultLog,
    .queryPageSize = if (@hasDecl(platform, "queryPageSize")) platform.queryPageSize else std.heap.defaultQueryPageSize,
    .page_size_min = if (@hasDecl(platform, "page_size_min")) platform.page_size_min else null,
    .page_size_max = if (@hasDecl(platform, "page_size_max")) platform.page_size_max else null,
};

pub fn main() void {
    std.log.info("Hello from Zenith", .{});
}
