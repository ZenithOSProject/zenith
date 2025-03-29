const builtin = @import("builtin");
const std = @import("std");
const arch = @field(@import("arch.zig"), @tagName(builtin.target.cpu.arch));
const log = std.log.scoped(.@"zenith.mem");

pub const phys = @import("mem/phys.zig");
pub const virt = @import("mem/virt.zig");

const PageList = std.SinglyLinkedList(void);
const RegionQueue = std.DoublyLinkedList(void);

pub const PageUsage = enum(u4) {
    invalid,
    pfn_database,
    free,
    conventional,
    dma,
    stack,
    page_table,
    max = 0b1111,
};

pub const Page = struct {
    node: PageList.Node = .{ .data = {} },
    info: packed struct(u64) {
        pfn: u52,
        usage: PageUsage,
        is_dirty: u1,
        reserved: u7,
    },
};

const PhysicalRegion = struct {
    node: RegionQueue.Node = .{ .data = {} },
    base_address: u64,
    page_count: usize,

    fn pages(self: *@This()) []Page {
        const ptr: [*]Page = @ptrFromInt(@intFromPtr(self) + @sizeOf(PhysicalRegion));
        return ptr[0..self.page_count];
    }
};

var free_pages: PageList = .{};
var regions: RegionQueue = .{};

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
    available: []const Range,
    fixed_allocator: std.mem.Allocator,

    pub fn deinit(self: Profile) void {
        self.fixed_allocator.free(self.modules);
        self.fixed_allocator.free(self.virtual_reserved);
        self.fixed_allocator.free(self.physical_reserved);
        self.fixed_allocator.free(self.available);
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
            .available = try self.fixed_allocator.dupe(Range, self.available),
            .fixed_allocator = self.fixed_allocator,
        };
    }
};

pub fn init(mem_profile: *const Profile, kernel_alloc: std.mem.Allocator) !void {
    phys.init(mem_profile, kernel_alloc);
    const heap_vmm = try virt.init(mem_profile, kernel_alloc);
    arch.paging.init(mem_profile);

    const mem_size = mem_profile.mem_kb * 1024;

    log.info("MMU initialized: {:.02} of RAM, {}k page size", .{
        std.fmt.fmtIntSizeDec(mem_size),
        std.heap.pageSize() / 1024,
    });

    for (mem_profile.available) |entry| {
        const length = entry.end - entry.start;
        const page_count = std.math.divCeil(usize, length, std.heap.pageSize()) catch unreachable;
        const reserved = std.mem.alignForward(usize, @sizeOf(PhysicalRegion) + @sizeOf(Page) * page_count, std.heap.pageSize());
        const aligned_length = page_count * std.heap.pageSize();

        if (aligned_length - reserved < std.heap.pageSize() * 8) {
            continue;
        }

        const region: *PhysicalRegion = @ptrFromInt(try heap_vmm.alloc(reserved / std.heap.pageSize(), physToVirt(entry.start), .{
            .kernel = true,
            .writable = true,
            .cachable = true,
        }) orelse continue);
        region.* = .{
            .base_address = entry.start,
            .page_count = page_count,
        };

        log.info("Tracking physical region {x} - {x}, {d}, {d} pages, {d} for PFDB", .{
            region.base_address,
            region.base_address + aligned_length,
            std.fmt.fmtIntSizeDec(aligned_length / 1024),
            region.page_count,
            std.fmt.fmtIntSizeDec(reserved / 1024),
        });

        const pages = region.pages();
        const reserved_page_count = reserved / std.heap.pageSize();

        for (pages, 0..) |*page, i| {
            page.* = Page{
                .info = .{
                    .pfn = @truncate((region.base_address + i * std.heap.pageSize()) >> 12),
                    .usage = if (i < reserved_page_count) .pfn_database else .free,
                    .is_dirty = @intFromBool(i >= reserved_page_count),
                    .reserved = 0,
                },
            };

            if (i >= reserved_page_count) {
                free_pages.prepend(&page.node);
            }
        }

        regions.append(&region.node);
    }
}

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
