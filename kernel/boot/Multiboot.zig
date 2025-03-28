const std = @import("std");
const arch = @import("../main.zig").arch;
const platform = @import("../main.zig").platform;
const mem = @import("../mem.zig");

pub const magic: i32 = 0x1BADB002;

pub const Header = extern struct {
    magic: u32 = MAGIC,
    flags: u32,
    checksum: i32,

    pub fn init(flags: u32) Header {
        return .{
            .flags = flags,
            .checksum = -(@as(i32, @intCast(MAGIC)) + @as(i32, @intCast(flags))),
        };
    }

    pub const MAGIC = 0x1BADB002;
    pub const Flags = struct {
        pub const ALIGN = 1 << 0;
        pub const MEMINFO = 1 << 1;
    };
};

pub const Info = extern struct {
    flags: u32,
    mem_lower: u32,
    mem_upper: u32,
    boot_device: u32,
    cmdline: u32,
    mods_count: u32,
    mods_addr: u32,
    binary: extern union {
        aout: extern struct {
            tabsize: u32,
            strsize: u32,
            addr: u32,
            reserved: u32,
        },
        elf: extern struct {
            num: u32,
            size: u32,
            addr: u32,
            shndx: u32,
        },
    },
    mmap_len: u32,
    mmap_addr: u32,
    drives_len: u32,
    drives_addr: u32,
    cfgtbl: u32,
    bootloader_name: u32,
    apm_table: u32,

    pub fn mmapIterator(self: *const Info) MemoryMap.Iterator {
        return .{
            .addr = self.mmap_addr,
            .end = self.mmap_len + self.mmap_addr,
        };
    }
};

pub const MemoryMap = packed struct {
    size: u32,
    addr: u64,
    len: u64,
    type: Type,

    pub const Type = enum(u32) {
        available = 1,
        reserved = 2,
        acpi_reclaim = 3,
        nvs = 4,
        badram = 5,
    };

    pub const Iterator = struct {
        addr: usize,
        end: usize,

        pub fn next(self: *Iterator) ?*MemoryMap {
            if (self.addr >= self.end) return null;

            @setRuntimeSafety(false);
            const entry: *MemoryMap = @as(*MemoryMap, @ptrFromInt(self.addr));
            self.addr += entry.size + @sizeOf(u32);
            return entry;
        }
    };
};

pub const ModuleList = packed struct {
    mod_start: u32,
    mod_end: u32,
    cmdline: u32,
    pad: u32,
};

pub var info: ?*const Info = null;

pub fn initMem(gpa: std.mem.Allocator, vaddr: mem.Range, paddr: mem.Range) !mem.Profile {
    std.debug.assert(info != null);

    var reserved_physical_mem = std.ArrayList(mem.Range).init(gpa);
    defer reserved_physical_mem.deinit();

    var reserved_virtual_mem = std.ArrayList(mem.Map).init(gpa);
    defer reserved_virtual_mem.deinit();

    var mmap_iter = info.?.mmapIterator();

    while (mmap_iter.next()) |entry| {
        if (entry.type != .available and entry.len < std.math.maxInt(usize)) {
            //FIXME: getting all the wrong values
            const end: usize = if (entry.addr > std.math.maxInt(usize) - entry.len) std.math.maxInt(usize) else @truncate(entry.addr + entry.len);
            try reserved_physical_mem.append(.{
                .start = @truncate(entry.addr),
                .end = end,
            });
        }
    }

    try reserved_virtual_mem.append(.{
        .virtual = vaddr,
        .physical = paddr,
    });

    const mb_region = mem.Range{
        .start = @intFromPtr(info.?),
        .end = @intFromPtr(info.?) + @sizeOf(Info),
    };
    const mb_physical = mem.Range{
        .start = mem.virtToPhys(mb_region.start),
        .end = mem.virtToPhys(mb_region.end),
    };
    try reserved_virtual_mem.append(.{
        .virtual = mb_region,
        .physical = mb_physical,
    });

    const mods_count = info.?.mods_count;
    const boot_modules = @as([*]ModuleList, @ptrFromInt(mem.physToVirt(info.?.mods_addr)))[0..mods_count];
    var modules = std.ArrayList(mem.Module).init(gpa);
    for (boot_modules) |module| {
        const virtual = mem.Range{
            .start = mem.physToVirt(module.mod_start),
            .end = mem.physToVirt(module.mod_end),
        };
        const physical = mem.Range{
            .start = module.mod_start,
            .end = module.mod_end,
        };
        try modules.append(.{
            .region = virtual,
            .name = std.mem.span(mem.physToVirt(@as([*:0]u8, @ptrFromInt(module.cmdline)))),
        });
        try reserved_virtual_mem.append(.{
            .physical = physical,
            .virtual = virtual,
        });
    }

    if (@hasDecl(arch, "initMem")) {
        try arch.initMem(&reserved_physical_mem, &reserved_virtual_mem);
    }

    if (@hasDecl(platform, "initMem")) {
        try platform.initMem(&reserved_physical_mem, &reserved_virtual_mem);
    }

    return mem.Profile{
        .vaddr = vaddr.toBlock(),
        .paddr = paddr.toBlock(),
        .mem_kb = info.?.mem_upper + info.?.mem_lower + 1024,
        .modules = modules.items,
        .physical_reserved = try reserved_physical_mem.toOwnedSlice(),
        .virtual_reserved = try reserved_virtual_mem.toOwnedSlice(),
        .fixed_allocator = gpa,
    };
}
