const std = @import("std");
const builtin = @import("builtin");
const Multiboot = @import("../../../boot/Multiboot.zig");
const arch = @import("../../x86.zig");
const io = @import("../io.zig");

export var multiboot: Multiboot.Header align(4) linksection(".multiboot") = Multiboot.Header.init(.{});

var stack_bytes: [64 * 1024]u8 align(16) linksection(".bss") = undefined;
var fxsave_region: [512]u8 align(16) linksection(".data") = undefined;

const com1 = io.SerialConsole{
    .baud = io.SerialConsole.DEFAULT_BAUDRATE,
    .port = .COM1,
};

var vga_console = io.VgaConsole.init();

export fn _start() callconv(.Naked) noreturn {
    asm volatile (
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
        \\ call %[_start_bootstrap:P]
        :
        : [stack_top] "i" (@as([*]align(16) u8, @ptrCast(&stack_bytes)) + @sizeOf(@TypeOf(stack_bytes))),
          [_start_bootstrap] "X" (&_start_bootstrap),
    );
}

fn _start_bootstrap() callconv(.C) void {
    arch.bootstrap();

    vga_console.reset();
    com1.reset() catch unreachable;

    var console = std.io.multiWriter(.{ vga_console.writer(), com1.writer() });

    _ = console.write("Hello, world\n") catch unreachable;
    _ = console.writer().print("{}\n", .{com1}) catch unreachable;
    //_ = console.writer().print("{s}\n", .{(std.zig.system.resolveTargetQuery(.{}) catch builtin.target).cpu.model.name}) catch unreachable;

    //while (true) {}
    @breakpoint();
}

pub const panic = std.debug.FullPanic(panicFunc);

fn panicFunc(msg: []const u8, first_trace_addr: ?usize) noreturn {
    var console = std.io.multiWriter(.{ vga_console.writer(), com1.writer() });
    _ = console.writer().print("\rPANIC: {s} ({?x})\n", .{ msg, first_trace_addr }) catch unreachable;
    while (true) {}
}

comptime {
    _ = _start;
    _ = multiboot;
}
