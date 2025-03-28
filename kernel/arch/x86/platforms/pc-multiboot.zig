const std = @import("std");
const builtin = @import("builtin");
const Multiboot = @import("../../../boot/Multiboot.zig");
const mem = @import("../../../mem.zig");
const arch = @import("../../x86.zig");
const io = @import("../io.zig");
const paging = @import("../paging.zig");

extern var kernel_paddr_offset: *u8;
extern var kernel_vaddr_offset: *u8;
extern var kernel_vaddr_end: *u8;

export var multiboot: Multiboot.Header align(4) linksection(".multiboot") = Multiboot.Header.init(Multiboot.Header.Flags.ALIGN | Multiboot.Header.Flags.MEMINFO);

var stack_bytes: [64 * 1024]u8 align(16) linksection(".bss.stack") = undefined;

const com1 = io.SerialConsole{
    .baud = io.SerialConsole.DEFAULT_BAUDRATE,
    .port = .COM1,
};

var vga_console = io.VgaConsole.init();
var mem_profile: mem.Profile = undefined;

const KERNEL_PAGE_NUMBER = 0xC0000000 >> 22;
const KERNEL_NUM_PAGES = 1;

var boot_page_directory: [1024]u32 align(4096) linksection(".rodata.boot") = init: {
    @setEvalBranchQuota(1024);
    var dir: [1024]u32 = undefined;

    dir[0] = 0x00000083;

    var i = 0;
    var idx = 1;

    while (i < KERNEL_PAGE_NUMBER - 1) : ({
        i += 1;
        idx += 1;
    }) {
        dir[idx] = 0;
    }

    i = 0;
    while (i < KERNEL_NUM_PAGES) : ({
        i += 1;
        idx += 1;
    }) {
        dir[idx] = 0x00000083 | (i << 22);
    }
    i = 0;
    while (i < 1024 - KERNEL_PAGE_NUMBER - KERNEL_NUM_PAGES) : ({
        i += 1;
        idx += 1;
    }) {
        dir[idx] = 0;
    }
    break :init dir;
};

export fn _start() linksection(".text.boot") callconv(.Naked) noreturn {
    asm volatile (
        \\mov %[boot_page_directory], %%ecx
        \\mov %%ecx, %%cr3
        \\
        \\mov %%cr4, %%ecx
        \\or $0x00000010, %%ecx
        \\mov %%ecx, %%cr4
        \\
        \\mov %%cr0, %%ecx
        \\or $0x80000000, %%ecx
        \\mov %%ecx, %%cr0
        \\
        \\jmp %[_start_higher:P]
        :
        : [boot_page_directory] "r" (&boot_page_directory),
          [_start_higher] "X" (&_start_higher),
    );
}

fn _start_higher() callconv(.C) noreturn {
    asm volatile (
        \\invlpg (0)
        \\
        \\movl %[stack_top], %%esp
        \\movl %%esp, %%ebp
        \\call %[_start_bootstrap:P]
        :
        : [stack_top] "i" (@as([*]align(16) u8, @ptrCast(&stack_bytes)) + @sizeOf(@TypeOf(stack_bytes))),
          [_start_bootstrap] "X" (&_start_bootstrap),
    );

    @breakpoint();
    unreachable;
}

fn _start_bootstrap() callconv(.C) void {
    const mb_info_addr = asm (
        \\mov %%ebx, %[res]
        : [res] "=r" (-> usize),
    ) + @intFromPtr(&kernel_paddr_offset);

    mem.ADDR_OFFSET = @intFromPtr(&kernel_paddr_offset);

    arch.bootstrap();

    const kmem_virt = mem.Range{
        .start = @intFromPtr(&kernel_vaddr_offset),
        .end = @intFromPtr(&kernel_vaddr_end),
    };

    Multiboot.info = @ptrFromInt(mb_info_addr);

    mem_profile = Multiboot.initMem(kernel_panic_allocator, kmem_virt, .{
        .start = mem.virtToPhys(kmem_virt.start),
        .end = mem.virtToPhys(kmem_virt.end),
    }) catch |err| std.debug.panic("Failed to initialize memory from multiboot: {s}", .{@errorName(err)});

    mem.phys.init(&mem_profile, kernel_panic_allocator);
    _ = mem.virt.init(&mem_profile, kernel_panic_allocator) catch |err| {
        const addr = if (@errorReturnTrace()) |trace| trace.instruction_addresses[0] else @frameAddress();
        std.debug.panicExtra(addr, "Failed to initialize virt-mmu: {s}", .{@errorName(err)});
    };
    paging.init(&mem_profile);

    vga_console.reset();
    com1.reset() catch unreachable;

    var console = std.io.multiWriter(.{ vga_console.writer(), com1.writer() });

    _ = console.write("Hello, world\n") catch unreachable;
    _ = console.writer().print("{}\n", .{mem_profile}) catch unreachable;

    @import("root").main();
}

pub const panic = std.debug.FullPanic(panicFunc);

var kernel_panic_allocator_bytes: [1024 * 1024]u8 = undefined;
var kernel_panic_allocator_state = std.heap.FixedBufferAllocator.init(kernel_panic_allocator_bytes[0..]);
const kernel_panic_allocator = kernel_panic_allocator_state.allocator();

fn panicFunc(msg: []const u8, first_trace_addr: ?usize) noreturn {
    var console = std.io.multiWriter(.{ vga_console.writer(), com1.writer() });

    _ = console.writer().print("\rPANIC: {s} ({?x})\n", .{ msg, first_trace_addr }) catch unreachable;

    if (first_trace_addr) |trace_addr| {
        _ = console.writer().writeAll("Stack trace:\n") catch unreachable;

        var it = std.debug.StackIterator.init(null, trace_addr);
        while (it.next()) |addr| {
            _ = console.writer().print("{x}\n", .{addr}) catch unreachable;
        }
    }

    while (true) {}
}

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    var console = std.io.multiWriter(.{ vga_console.writer(), com1.writer() });

    _ = console.writer().print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
}

comptime {
    _ = _start;
    _ = multiboot;
}
