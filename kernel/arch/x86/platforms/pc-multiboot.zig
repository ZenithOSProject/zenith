const Multiboot = @import("../../../boot/Multiboot.zig");
const arch = @import("../../x86.zig");
const io = @import("../io.zig");

export var multiboot: Multiboot.Header align(4) linksection(".multiboot") = Multiboot.Header.init(.{});

var stack_bytes: [16 * 1024]u8 align(16) linksection(".bss") = undefined;

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
    //arch.bootstrap();

    var com1 = io.SerialConsole{
        .port = .COM1,
    };
    com1.reset() catch unreachable;

    com1.writer().print("{}\n", .{com1}) catch unreachable;

    while (true) {}
}

comptime {
    _ = _start;
    _ = multiboot;
}
