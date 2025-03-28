const std = @import("std");
const io = @import("qemu-virt/io.zig");

var stack_bytes: [64 * 1024]u8 align(16) linksection(".bss") = undefined;

export fn _start() callconv(.Naked) noreturn {
    asm volatile (
        \\ldr x30, =%[stack_top]
        \\mov sp, x30
        \\bl %[_start_bootstrap]
        :
        : [stack_top] "i" (@as([*]align(16) u8, @ptrCast(&stack_bytes)) + @sizeOf(@TypeOf(stack_bytes))),
          [_start_bootstrap] "X" (&_start_bootstrap),
    );
}

fn _start_bootstrap() callconv(.C) void {
    const el1: u64 = 0b11 << 20;
    asm volatile (
        \\msr cpacr_el1, %[el1]
        :
        : [el1] "r" (el1),
    );

    var serial = io.SerialConsole{};
    _ = serial.write("Hello, world\n") catch unreachable;
    _ = serial.writer().print("{}\n", .{serial}) catch unreachable;
    while (true) {}
}

pub const panic = std.debug.FullPanic(panicFunc);

fn panicFunc(msg: []const u8, first_trace_addr: ?usize) noreturn {
    _ = first_trace_addr;
    var serial = io.SerialConsole{};
    _ = serial.write(msg) catch unreachable;
    while (true) {}
}
