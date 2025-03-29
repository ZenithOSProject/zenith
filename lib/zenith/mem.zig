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
    modules: []const Module,
    virtual_reserved: []const Map,
    physical_reserved: []const Range,
    fixed_allocator: std.mem.Allocator,

    pub fn deinit(self: Profile) void {
        self.fixed_allocator.free(self.modules);
        self.fixed_allocator.free(self.virtual_reserved);
        self.fixed_allocator.free(self.physical_reserved);
    }

    pub fn expandReserved(self: Profile, physical_reserved: []const Range, virtual_reserved: []const Map) !Profile {
        var new_virtual_reserved = std.ArrayList(Map).init(self.fixed_allocator);
        errdefer new_virtual_reserved.deinit();
        try new_virtual_reserved.appendSlice(self.virtual_reserved);
        try new_virtual_reserved.appendSlice(virtual_reserved);

        var new_physical_reserved = std.ArrayList(Range).init(self.fixed_allocator);
        errdefer new_physical_reserved.deinit();
        try new_physical_reserved.appendSlice(self.physical_reserved);
        try new_physical_reserved.appendSlice(physical_reserved);

        return .{
            .vaddr = self.vaddr,
            .paddr = self.paddr,
            .mem_kb = self.mem_kb,
            .modules = try self.fixed_allocator.dupe(Module, self.modules),
            .virtual_reserved = new_virtual_reserved.items,
            .physical_reserved = new_physical_reserved.items,
            .fixed_allocator = self.fixed_allocator,
        };
    }
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

test "virtToPhys" {
    const old_addr_offset = ADDR_OFFSET;
    defer ADDR_OFFSET = old_addr_offset;

    ADDR_OFFSET = 0xC0000000;

    try std.testing.expectEqual(virtToPhys(ADDR_OFFSET), 0);
    try std.testing.expectEqual(virtToPhys(ADDR_OFFSET + 123), 123);
    try std.testing.expectEqual(@intFromPtr(virtToPhys(@as(*align(1) usize, @ptrFromInt(ADDR_OFFSET + 123)))), 123);
}

test "physToVirt" {
    const old_addr_offset = ADDR_OFFSET;
    defer ADDR_OFFSET = old_addr_offset;

    ADDR_OFFSET = 0xC0000000;

    try std.testing.expectEqual(physToVirt(@as(usize, 0)), ADDR_OFFSET + 0);
    try std.testing.expectEqual(physToVirt(@as(usize, 123)), ADDR_OFFSET + 123);
    try std.testing.expectEqual(@intFromPtr(physToVirt(@as(*align(1) usize, @ptrFromInt(123)))), ADDR_OFFSET + 123);
}
