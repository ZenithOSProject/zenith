const std = @import("std");
const builtin = @import("builtin");
const Multiboot = @import("../../../boot/Multiboot.zig");
const arch = @import("../../x86.zig");
const io = @import("../io.zig");

export var multiboot: Multiboot.Header align(4) linksection(".multiboot") = Multiboot.Header.init(.{});

var stack_bytes: [64 * 1024]u8 align(16) linksection(".bss.stack") = undefined;

const com1 = io.SerialConsole{
    .baud = io.SerialConsole.DEFAULT_BAUDRATE,
    .port = .COM1,
};

var vga_console = io.VgaConsole.init();

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
    arch.bootstrap();

    vga_console.reset();
    com1.reset() catch unreachable;

    var console = std.io.multiWriter(.{ vga_console.writer(), com1.writer() });

    _ = console.write("Hello, world\n") catch unreachable;
    _ = console.writer().print("{}\n", .{com1}) catch unreachable;

    @import("root").main();
    //_ = console.writer().print("{s}\n", .{(std.zig.system.resolveTargetQuery(.{}) catch builtin.target).cpu.model.name}) catch unreachable;
}

pub const panic = std.debug.FullPanic(panicFunc);

extern var __debug_info_start: *u8;
extern var __debug_info_end: *u8;
extern var __debug_abbrev_start: *u8;
extern var __debug_abbrev_end: *u8;
extern var __debug_str_start: *u8;
extern var __debug_str_end: *u8;
extern var __debug_line_start: *u8;
extern var __debug_line_end: *u8;
extern var __debug_ranges_start: *u8;
extern var __debug_ranges_end: *u8;

var kernel_panic_allocator_bytes: [100 * 1024]u8 = undefined;
var kernel_panic_allocator_state = std.heap.FixedBufferAllocator.init(kernel_panic_allocator_bytes[0..]);
const kernel_panic_allocator = kernel_panic_allocator_state.allocator();

fn openDwarfInfo() !std.debug.Dwarf {
    var sections: std.debug.Dwarf.SectionArray = std.debug.Dwarf.null_section_array;

    const debug_info_ptr: [*]u8 = @ptrFromInt(@as(usize, @intFromPtr(&__debug_info_start)));
    const debug_info_size = @intFromPtr(&__debug_info_end) - @intFromPtr(&__debug_info_start);
    sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_info)] = .{
        .data = debug_info_ptr[0..debug_info_size],
        //.virtual_address = @intFromPtr(__debug_info_start),
        .owned = false,
    };

    const debug_abbrev_ptr: [*]u8 = @ptrFromInt(@as(usize, @intFromPtr(&__debug_abbrev_start)));
    const debug_abbrev_size = @intFromPtr(&__debug_abbrev_end) - @intFromPtr(&__debug_abbrev_start);
    sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_abbrev)] = .{
        .data = debug_abbrev_ptr[0..debug_abbrev_size],
        //.virtual_address = @intFromPtr(__debug_abbrev_start),
        .owned = false,
    };

    try com1.writer().print("{x} {any}\n", .{ @as(usize, @intFromPtr(&__debug_abbrev_start)), debug_abbrev_ptr[0..debug_abbrev_size] });

    const debug_str_ptr: [*]u8 = @ptrFromInt(@as(usize, @intFromPtr(&__debug_str_start)));
    const debug_str_size = @intFromPtr(&__debug_str_end) - @intFromPtr(&__debug_str_start);
    sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_str)] = .{
        .data = debug_str_ptr[0..debug_str_size],
        //.virtual_address = @intFromPtr(__debug_str_start),
        .owned = false,
    };

    const debug_ranges_ptr: [*]u8 = @ptrFromInt(@as(usize, @intFromPtr(&__debug_ranges_start)));
    const debug_ranges_size = @intFromPtr(&__debug_ranges_end) - @intFromPtr(&__debug_ranges_start);
    sections[@intFromEnum(std.debug.Dwarf.Section.Id.debug_ranges)] = .{
        .data = debug_ranges_ptr[0..debug_ranges_size],
        //.virtual_address = @intFromPtr(__debug_ranges_start),
        .owned = false,
    };

    var di: std.debug.Dwarf = .{
        .endian = builtin.target.cpu.arch.endian(),
        .sections = sections,
        .is_macho = false,
    };

    try std.debug.Dwarf.open(&di, kernel_panic_allocator);
    return di;
}

fn panicFunc(msg: []const u8, first_trace_addr: ?usize) noreturn {
    var console = com1.writer();

    _ = console.print("\rPANIC: {s} ({?x})\n", .{ msg, first_trace_addr }) catch unreachable;

    if (first_trace_addr) |trace_addr| {
        var dwarf = openDwarfInfo() catch |err| {
            _ = console.print("Failed to open Dwarf: {s}\n", .{@errorName(err)}) catch unreachable;
            if (@errorReturnTrace()) |trace| {
                for (trace.instruction_addresses) |addr| {
                    _ = console.print("{x}\n", .{addr}) catch unreachable;
                }
            }
            while (true) {}
        };
        defer dwarf.deinit(kernel_panic_allocator);

        _ = console.writeAll("Stack trace:\n") catch unreachable;

        var it = std.debug.StackIterator.init(null, trace_addr);
        while (it.next()) |addr| {
            if (dwarf.getSymbol(kernel_panic_allocator, addr) catch null) |sym| {
                _ = console.print("{s}\n", .{sym.name}) catch unreachable;
            } else {
                _ = console.print("{x}\n", .{addr}) catch unreachable;
            }
        }
    }

    while (true) {}
}

comptime {
    _ = _start;
    _ = multiboot;
}
