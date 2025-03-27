const Multiboot = @import("../../../boot/Multiboot.zig");
const arch = @import("../../x86.zig");
const io = @import("../io.zig");

export var multiboot: Multiboot.Header align(4) linksection(".multiboot") = Multiboot.Header.init(.{});

var stack_bytes: [64 * 1024]u8 align(16) linksection(".bss") = undefined;

const com1 = io.SerialConsole{
    .baud = io.SerialConsole.DEFAULT_BAUDRATE,
    .port = .COM1,
};

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

    com1.reset() catch unreachable;
    _ = com1.write("Hello, world\n") catch unreachable;
    _ = com1.writer().print("{}", .{1}) catch unreachable;

    while (true) {}
}

comptime {
    _ = _start;
    _ = multiboot;
}
