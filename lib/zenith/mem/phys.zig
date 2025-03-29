const builtin = @import("builtin");
const std = @import("std");
const arch = @field(@import("../arch.zig"), @tagName(builtin.target.cpu.arch));
const mem = @import("../mem.zig");
const Bitmap = @import("../bitmap.zig").Bitmap(null, u32);
const log = std.log.scoped(.@"zenith.mem.phys");

var mbitmap: Bitmap = undefined;

pub fn setAddr(addr: usize) error{OutOfBounds}!void {
    try mbitmap.setEntry(@intCast(addr / std.heap.pageSize()));
}

pub fn isSet(addr: usize) error{OutOfBounds}!bool {
    return mbitmap.isSet(@intCast(addr / std.heap.pageSize()));
}

pub fn alloc() ?usize {
    if (mbitmap.setFirstFree()) |entry| {
        return entry * std.heap.pageSize();
    }
    return null;
}

pub fn free(addr: usize) error{ OutOfBounds, NotAllocated }!void {
    const idx: usize = @intCast(addr / std.heap.pageSize());
    if (try mbitmap.isSet(idx)) {
        try mbitmap.clearEntry(idx);
    } else {
        return error.NotAllocated;
    }
}

pub fn blocksFree() usize {
    return mbitmap.free_count;
}

pub fn init(memprofile: *const mem.Profile, allocator: std.mem.Allocator) void {
    mbitmap = Bitmap.init(
        memprofile.mem_kb * 1024 / std.heap.pageSize(),
        allocator,
    ) catch |e| std.debug.panic("Failed to allocate physical memory bitmap: {s}", .{@errorName(e)});

    for (memprofile.physical_reserved) |entry| {
        var addr = std.mem.alignBackward(usize, entry.start, std.heap.pageSize());
        var end = entry.end - 1;
        if (end <= std.math.maxInt(usize) - std.heap.pageSize()) {
            end = std.mem.alignForward(usize, end, std.heap.pageSize());
        }

        while (addr < end) : (addr += std.heap.pageSize()) setAddr(addr) catch |e| switch (e) {
            error.OutOfBounds => break,
        };

        log.info("Reserving physical memory {x} - {x}", .{ entry.start, end });
    }
}
