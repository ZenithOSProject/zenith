const std = @import("std");
const zenith = @import("zenith");
const mem = zenith.mem;
const paging = zenith.arch.x86.paging;
const io = @import("pc/io.zig");

var kernel_alloc_bytes: [1024 * 1024]u8 = undefined;
var kernel_alloc_state = std.heap.FixedBufferAllocator.init(kernel_alloc_bytes[0..]);

pub const kernel_alloc = kernel_alloc_state.allocator();

const com1 = io.SerialConsole{
    .baud = io.SerialConsole.DEFAULT_BAUDRATE,
    .port = .COM1,
};

var vga_console = io.VgaConsole.init();
var mem_profile: mem.Profile = undefined;

pub fn bootstrap(init_mem_profile: mem.Profile) void {
    const vga_console_addr = mem.virtToPhys(@as(usize, @intFromPtr(vga_console.buffer().ptr)));
    const vga_console_region = mem.Range{
        .start = vga_console_addr,
        .end = vga_console_addr + 32 * 1024,
    };

    mem_profile = init_mem_profile.expandReserved(&.{}, &.{
        .{
            .physical = vga_console_region,
            .virtual = .{
                .start = mem.physToVirt(vga_console_region.start),
                .end = mem.physToVirt(vga_console_region.end),
            },
        },
    }) catch |err| {
        const addr = if (@errorReturnTrace()) |trace| trace.instruction_addresses[0] else @frameAddress();
        std.debug.panicExtra(addr, "Failed to expand memory profile: {s}", .{@errorName(err)});
    };

    _ = mem.init(&mem_profile, kernel_alloc) catch |err| {
        const addr = if (@errorReturnTrace()) |trace| trace.instruction_addresses[0] else @frameAddress();
        std.debug.panicExtra(addr, "Failed to initialize mmu: {s}", .{@errorName(err)});
    };

    vga_console.reset();
    com1.reset() catch unreachable;
}

pub const panic = std.debug.FullPanic(panicFunc);

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

pub fn queryPageSize() usize {
    // TODO: support runtime page size
    return paging.PAGE_SIZE_4KB;
}

pub const page_size_min = paging.PAGE_SIZE_4KB;
pub const page_size_max = paging.PAGE_SIZE_4KB;
