const std = @import("std");

pub const phys = @import("mem/phys.zig");
pub const virt = @import("mem/virt.zig");

pub const Module = struct {
    region: Range,
    name: []const u8,
};

pub const Map = struct {
    virtual: Range,
    physical: ?Range,
};

pub const Range = struct {
    start: usize,
    end: usize,

    pub fn toBlock(self: Range) Block {
        return .{
            .end = @ptrFromInt(self.end),
            .start = @ptrFromInt(self.start),
        };
    }
};

pub const Block = struct {
    end: [*]u8,
    start: [*]u8,
};

pub const Profile = struct {
    vaddr: Block,
    paddr: Block,
    mem_kb: usize,
    modules: []Module,
    virtual_reserved: []Map,
    physical_reserved: []Range,
    fixed_allocator: std.mem.Allocator,
};

pub var ADDR_OFFSET: usize = 0;

pub fn virtToPhys(v: anytype) @TypeOf(v) {
    const T = @TypeOf(v);
    return switch (@typeInfo(T)) {
        .pointer => @ptrFromInt(@intFromPtr(v) - ADDR_OFFSET),
        .int => v - ADDR_OFFSET,
        else => @compileError("Only pointers and integers are supported"),
    };
}

pub fn physToVirt(p: anytype) @TypeOf(p) {
    const T = @TypeOf(p);
    return switch (@typeInfo(T)) {
        .pointer => @ptrFromInt(@intFromPtr(p) + ADDR_OFFSET),
        .int => p + ADDR_OFFSET,
        else => @compileError("Only pointers and integers are supported"),
    };
}
