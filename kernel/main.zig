const builtin = @import("builtin");
const std = @import("std");
const Self = @This();

pub usingnamespace @import("common_main.zig");

pub fn main() void {
    std.log.info("Hello from Zenith", .{});
}

comptime {
    _ = Self.arch;
}
