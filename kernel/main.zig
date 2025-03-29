const builtin = @import("builtin");
const std = @import("std");
const options = @import("options");
const Self = @This();

pub usingnamespace @import("common_main.zig");

pub fn main() void {
    std.log.info("Hello from Zenith v{}", .{options.version});
}

comptime {
    _ = Self.arch;
    _ = @import("zenith");
}

test {
    _ = @import("zenith");
}
