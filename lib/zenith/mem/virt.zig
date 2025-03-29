const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const arch = @field(@import("../arch.zig"), @tagName(builtin.target.cpu.arch));
const Bitmap = @import("../bitmap.zig").Bitmap;
const mem = @import("../mem.zig");
const phys = @import("phys.zig");
const log = std.log.scoped(.@"zenith.mem.virt");

pub const Attributes = struct {
    kernel: bool,
    writable: bool,
    cachable: bool,
};

const Allocation = struct {
    physical: std.ArrayList(usize),
};

pub const MapperError = error{
    InvalidVirtualAddress,
    InvalidPhysicalAddress,
    AddressMismatch,
    MisalignedVirtualAddress,
    MisalignedPhysicalAddress,
    NotMapped,
};

pub const Error = error{
    NotAllocated,
    AlreadyAllocated,
    PhysicalAlreadyAllocated,
    PhysicalVirtualMismatch,
    InvalidVirtAddresses,
    InvalidPhysAddresses,
    OutOfMemory,
};

pub var kernel_vmm: Manager(arch.VmmPayload) = undefined;

pub fn Mapper(comptime Payload: type) type {
    return struct {
        mapFn: *const fn (
            virtual_start: usize,
            virtual_end: usize,
            physical_start: usize,
            physical_end: usize,
            attrs: Attributes,
            allocator: Allocator,
            spec: Payload,
        ) (Allocator.Error || MapperError)!void,
        unmapFn: *const fn (
            virtual_start: usize,
            virtual_end: usize,
            allocator: Allocator,
            spec: Payload,
        ) MapperError!void,
    };
}

pub fn Manager(comptime Payload: type) type {
    return struct {
        const Self = @This();

        bmp: Bitmap(null, usize),
        start: usize,
        end: usize,
        allocator: Allocator,
        allocations: std.AutoHashMap(usize, Allocation),
        mapper: Mapper(Payload),
        payload: Payload,

        pub fn init(start: usize, end: usize, allocator: Allocator, mapper: Mapper(Payload), payload: Payload) Allocator.Error!Self {
            const size = end - start;
            const bmp = try Bitmap(null, usize).init(std.mem.alignForward(usize, size, std.heap.pageSize()) / std.heap.pageSize(), allocator);
            return Self{
                .bmp = bmp,
                .start = start,
                .end = end,
                .allocator = allocator,
                .allocations = std.AutoHashMap(usize, Allocation).init(allocator),
                .mapper = mapper,
                .payload = payload,
            };
        }

        pub fn copy(self: *const Self) Allocator.Error!Self {
            var clone = Self{
                .bmp = try self.bmp.clone(),
                .start = self.start,
                .end = self.end,
                .allocator = self.allocator,
                .allocations = std.AutoHashMap(usize, Allocation).init(self.allocator),
                .mapper = self.mapper,
                .payload = self.payload,
            };
            var it = self.allocations.iterator();
            while (it.next()) |entry| {
                var list = std.ArrayList(usize).init(self.allocator);
                for (entry.value_ptr.physical.items) |block| {
                    _ = try list.append(block);
                }
                _ = try clone.allocations.put(entry.key_ptr.*, Allocation{ .physical = list });
            }
            return clone;
        }

        pub fn deinit(self: *Self) void {
            self.bmp.deinit();
            var it = self.allocations.iterator();
            while (it.next()) |entry| entry.value_ptr.physical.deinit();
            self.allocations.deinit();
        }

        pub fn virtToPhys(self: *const Self, v: usize) Error!usize {
            var it = self.allocations.iterator();
            while (it.next()) |entry| {
                const vaddr = entry.key_ptr.*;

                const allocation = entry.value_ptr.*;
                if (vaddr <= v and vaddr + (allocation.physical.items.len * std.heap.pageSize()) > v) {
                    const block_number = (v - vaddr) / std.heap.pageSize();
                    const block_offset = (v - vaddr) % std.heap.pageSize();
                    return allocation.physical.items[block_number] + block_offset;
                }
            }
            return Error.NotAllocated;
        }

        pub fn physToVirt(self: *const Self, p: usize) Error!usize {
            var it = self.allocations.iterator();
            while (it.next()) |entry| {
                const vaddr = entry.key_ptr.*;
                const allocation = entry.value_ptr.*;

                for (allocation.physical.items, 0..) |block, i| {
                    if (block <= p and block + std.heap.pageSize() > p) {
                        const block_addr = vaddr + i * std.heap.pageSize();
                        const block_offset = p % std.heap.pageSize();
                        return block_addr + block_offset;
                    }
                }
            }
            return Error.NotAllocated;
        }

        pub fn isSet(self: *const Self, v: usize) error{OutOfBounds}!bool {
            if (v < self.start) {
                return error.OutOfBounds;
            }
            return self.bmp.isSet((v - self.start) / std.heap.pageSize());
        }

        pub fn set(self: *Self, virtual: mem.Range, physical: ?mem.Range, attrs: Attributes) (Error || Allocator.Error || MapperError || error{OutOfBounds})!void {
            var virt = virtual.start;
            while (virt < virtual.end) : (virt += std.heap.pageSize()) {
                if (try self.isSet(virt)) {
                    return Error.AlreadyAllocated;
                }
            }
            if (virtual.start > virtual.end) {
                return Error.InvalidVirtAddresses;
            }

            if (physical) |p| {
                if (virtual.end - virtual.start != p.end - p.start) {
                    return Error.PhysicalVirtualMismatch;
                }
                if (p.start > p.end) {
                    return Error.InvalidPhysAddresses;
                }
                var phys2 = p.start;
                while (phys2 < p.end) : (phys2 += std.heap.pageSize()) {
                    if (try phys.isSet(phys2)) {
                        return Error.PhysicalAlreadyAllocated;
                    }
                }
            }

            var phys_list = std.ArrayList(usize).init(self.allocator);

            virt = virtual.start;
            while (virt < virtual.end) : (virt += std.heap.pageSize()) {
                try self.bmp.setEntry((virt - self.start) / std.heap.pageSize());
            }

            if (physical) |p| {
                var phys2 = p.start;
                while (phys2 < p.end) : (phys2 += std.heap.pageSize()) {
                    try phys.setAddr(phys2);
                    try phys_list.append(phys2);
                }
            }

            _ = try self.allocations.put(virtual.start, Allocation{ .physical = phys_list });

            if (physical) |p| {
                try self.mapper.mapFn(virtual.start, virtual.end, p.start, p.end, attrs, self.allocator, self.payload);
            }
        }

        pub fn alloc(self: *Self, num: usize, virtual_addr: ?usize, attrs: Attributes) Allocator.Error!?usize {
            if (num == 0) return null;
            if (phys.blocksFree() >= num and self.bmp.free_count >= num) {
                if (self.bmp.setContiguous(num, if (virtual_addr) |a| (a - self.start) / std.heap.pageSize() else null)) |entry| {
                    var block_list = std.ArrayList(usize).init(self.allocator);
                    try block_list.ensureUnusedCapacity(num);

                    var i: usize = 0;
                    const vaddr_start = self.start + entry * std.heap.pageSize();
                    var vaddr = vaddr_start;
                    while (i < num) : (i += 1) {
                        const addr = phys.alloc() orelse unreachable;
                        try block_list.append(addr);
                        self.mapper.mapFn(
                            vaddr,
                            vaddr + std.heap.pageSize(),
                            addr,
                            addr + std.heap.pageSize(),
                            attrs,
                            self.allocator,
                            self.payload,
                        ) catch |e| std.debug.panic("Failed to map virtual memory: 0x{x}: {s}\n", .{
                            vaddr,
                            @errorName(e),
                        });
                        vaddr += std.heap.pageSize();
                    }
                    _ = try self.allocations.put(vaddr_start, Allocation{ .physical = block_list });
                    return vaddr_start;
                }
            }
            return null;
        }

        pub fn copyData(
            self: *Self,
            other: *const Self,
            comptime from: bool,
            data: if (from) []const u8 else []u8,
            address: usize,
        ) (error{OutOfBounds} || Error || Allocator.Error)!void {
            if (data.len == 0) {
                return;
            }
            const start_addr = std.mem.alignBackward(address, std.heap.pageSize());
            const end_addr = std.mem.alignForward(address + data.len, std.heap.pageSize());

            if (end_addr >= other.end or start_addr < other.start) {
                return error.OutOfBounds;
            }

            var blocks = std.ArrayList(usize).init(self.allocator);
            defer blocks.deinit();
            var it = other.allocations.iterator();
            while (it.next()) |allocation| {
                const virtual = allocation.key_ptr.*;
                const physical = allocation.value_ptr.*.physical.items;
                if (start_addr >= virtual and virtual + physical.len * std.heap.pageSize() >= end_addr) {
                    const first_block_idx = (start_addr - virtual) / std.heap.pageSize();
                    const last_block_idx = (end_addr - virtual) / std.heap.pageSize();

                    try blocks.appendSlice(physical[first_block_idx..last_block_idx]);
                }
            }
            if (blocks.items.len != std.mem.alignForward(data.len, std.heap.pageSize()) / std.heap.pageSize()) {
                return Error.NotAllocated;
            }

            if (self.bmp.setContiguous(blocks.items.len, null)) |entry| {
                const v_start = entry * std.heap.pageSize() + self.start;
                for (blocks.items, 0..) |block, i| {
                    const v = v_start + i * std.heap.pageSize();
                    const v_end = v + std.heap.pageSize();
                    const p = block;
                    const p_end = p + std.heap.pageSize();
                    self.mapper.mapFn(v, v_end, p, p_end, .{
                        .kernel = true,
                        .writable = true,
                        .cachable = false,
                    }, self.allocator, self.payload) catch |e| {
                        if (i > 0) {
                            self.mapper.unmapFn(v_start, v_end, self.allocator, self.payload) catch |e2| std.debug.panic("Failed to unmap virtual region 0x{X} -> 0x{X}: {}\n", .{ v_start, v_end, e2 });
                        }
                        std.debug.panic("Failed to map virtual region 0x{X} -> 0x{X} to 0x{X} -> 0x{X}: {}\n", .{ v, v_end, p, p_end, e });
                    };
                }
                const align_offset = address - start_addr;
                const data_copy = @as([*]u8, @ptrFromInt(v_start + align_offset))[0..data.len];
                if (from) {
                    std.mem.copy(u8, data_copy, data);
                } else {
                    std.mem.copy(u8, data, data_copy);
                }
            } else {
                return Error.OutOfMemory;
            }
        }

        pub fn free(self: *Self, vaddr: usize) (error{OutOfBounds} || Error)!void {
            const entry = (vaddr - self.start) / std.heap.pageSize();
            if (try self.bmp.isSet(entry)) {
                const allocation = self.allocations.get(vaddr).?;
                const physical = allocation.physical;
                defer physical.deinit();
                const num_physical_allocations = physical.items.len;
                for (physical.items, 0..) |block, i| {
                    try self.bmp.clearEntry(entry + i);
                    phys.free(block) catch |e| std.debug.panic("Failed to free PMM reserved memory at 0x{X}: {}\n", .{
                        block * std.heap.pageSize(),
                        e,
                    });
                }

                const region_start = vaddr;
                const region_end = vaddr + (num_physical_allocations * std.heap.pageSize());
                self.mapper.unmapFn(
                    region_start,
                    region_end,
                    self.allocator,
                    self.payload,
                ) catch |e| std.debug.panic("Failed to unmap VMM reserved memory from 0x{X} to 0x{X}: {}\n", .{ region_start, region_end, e });
                assert(self.allocations.remove(vaddr));
            } else {
                return Error.NotAllocated;
            }
        }
    };
}

pub fn init(memprofile: *const mem.Profile, allocator: std.mem.Allocator) Allocator.Error!*Manager(arch.VmmPayload) {
    log.info("Creating kernel VMM for {x} - {x}", .{
        @intFromPtr(memprofile.paddr.start),
        std.math.maxInt(usize),
    });

    kernel_vmm = try Manager(arch.VmmPayload).init(
        @intFromPtr(memprofile.paddr.start),
        std.math.maxInt(usize),
        allocator,
        arch.VMM_MAPPER,
        arch.KERNEL_VMM_PAYLOAD,
    );

    for (memprofile.virtual_reserved) |entry| {
        const virtual = mem.Range{
            .start = std.mem.alignBackward(usize, entry.virtual.start, std.heap.pageSize()),
            .end = std.mem.alignForward(usize, entry.virtual.end, std.heap.pageSize()),
        };
        const physical: ?mem.Range = if (entry.physical) |p|
            mem.Range{
                .start = std.mem.alignBackward(usize, p.start, std.heap.pageSize()),
                .end = std.mem.alignForward(usize, p.end, std.heap.pageSize()),
            }
        else
            null;

        log.info("Reserving virtual memory {x} - {x} / {?x} - {?x}", .{
            virtual.start,
            virtual.end,
            if (physical) |p| p.start else null,
            if (physical) |p| p.end else null,
        });

        kernel_vmm.set(virtual, physical, .{ .kernel = true, .writable = true, .cachable = true }) catch |e| switch (e) {
            Error.AlreadyAllocated => {},
            else => std.debug.panicExtra(
                if (@errorReturnTrace()) |trace| trace.instruction_addresses[0] else @frameAddress(),
                "Failed mapping region in VMM ({x} - {x} / {?x} - {?x}): {s}",
                .{
                    virtual.start,
                    virtual.end,
                    if (physical) |p| p.start else null,
                    if (physical) |p| p.end else null,
                    @errorName(e),
                },
            ),
        };
    }
    return &kernel_vmm;
}
