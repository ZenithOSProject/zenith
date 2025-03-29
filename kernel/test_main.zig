const builtin = @import("builtin");
const std = @import("std");
const build_options = @import("options");
const Self = @This();

pub usingnamespace @import("common_main.zig");

comptime {
    _ = Self.platform;
}

pub fn main() void {
    @disableInstrumentation();

    var passed: u64 = 0;
    var skipped: u64 = 0;
    var failed: u64 = 0;

    for (builtin.test_functions) |test_fn| {
        if (test_fn.func()) |_| {
            std.log.info("{s}... PASS", .{test_fn.name});
        } else |err| {
            if (err != error.SkipSigTest) {
                failed += 1;
                std.log.info("{s}... FAIL\n{}", .{ test_fn.name, err });
                continue;
            }

            skipped += 1;
            std.log.info("{s}... SKIP", .{test_fn.name});
            continue;
        }
        passed += 1;
    }

    std.log.info("{} passed, {} skipped, {} failed", .{
        passed,
        skipped,
        failed,
    });
}
