const std = @import("std");
const arch = @import("../main.zig").arch;
const mem = @import("../mem.zig");
const Bitmap = @import("../bitmap.zig").Bitmap(null, u32);

pub const BLOCK_SIZE: usize = arch.MEMORY_BLOCK_SIZE;

var mbitmap: Bitmap = undefined;

pub fn setAddr(addr: usize) error{OutOfBounds}!void {
    try mbitmap.setEntry(@intCast(addr / BLOCK_SIZE));
}

pub fn isSet(addr: usize) error{OutOfBounds}!bool {
    return mbitmap.isSet(@intCast(addr / BLOCK_SIZE));
}

pub fn alloc() ?usize {
    if (mbitmap.setFirstFree()) |entry| {
        return entry * BLOCK_SIZE;
    }
    return null;
}

pub fn free(addr: usize) error{ OutOfBounds, NotAllocated }!void {
    const idx: usize = @intCast(addr / BLOCK_SIZE);
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
    mbitmap = Bitmap.init(memprofile.mem_kb * 1024 / BLOCK_SIZE, allocator) catch |e| std.debug.panic("Failed to allocate physical memory bitmap: {s}", .{@errorName(e)});

    for (memprofile.physical_reserved) |entry| {
        var addr = std.mem.alignBackward(usize, entry.start, BLOCK_SIZE);
        var end = entry.end - 1;
        if (end <= std.math.maxInt(usize) - BLOCK_SIZE) {
            end = std.mem.alignForward(usize, end, BLOCK_SIZE);
        }

        while (addr < end) : (addr += BLOCK_SIZE) setAddr(addr) catch |e| switch (e) {
            error.OutOfBounds => break,
        };
    }
}
