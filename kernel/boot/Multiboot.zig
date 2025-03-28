const std = @import("std");
const mem = @import("../mem.zig");

pub const magic: i32 = 0x1BADB002;

pub const Header = extern struct {
    magic: i32 = MAGIC,
    flags: i32,
    checksum: i32,

    pub fn init(flags: i32) Header {
        return .{
            .flags = flags,
            .checksum = -(MAGIC + flags),
        };
    }

    pub const MAGIC = 0x1BADB002;
    pub const Flags = struct {
        pub const ALIGN = 1 << 0;
        pub const MEMINFO = 1 << 1;
    };
};

pub const Info = packed struct {
    flags: u32,
    mem_lower: u32,
    mem_upper: u32,
    boot_device: u32,
    cmdline: u32,
    mods_count: u32,
    mods_addr: u32,
    binary: packed union {
        aout: packed struct {
            tabsize: u32,
            strsize: u32,
            addr: u32,
            reserved: u32,
        },
        elf: packed struct {
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
};

pub const MemoryMap = packed struct {
    size: u32,
    addr: u64,
    len: u64,
    type: u32,
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

    const mmap_addr = info.?.mmap_addr;
    const num_mmap_entries = info.?.mmap_len / @sizeOf(MemoryMap);

    var reserved_physical_mem = std.ArrayList(mem.Range).init(gpa);
    defer reserved_physical_mem.deinit();

    var reserved_virtual_mem = std.ArrayList(mem.Map).init(gpa);
    defer reserved_virtual_mem.deinit();

    const mem_map = @as([*]MemoryMap, @ptrFromInt(mmap_addr))[0..num_mmap_entries];

    for (mem_map) |entry| {
        if (entry.type != 1 and entry.len < std.math.maxInt(usize)) {
            const end: usize = if (entry.addr > std.math.maxInt(usize) - entry.len) std.math.maxInt(usize) else @truncate(entry.addr + entry.len);
            try reserved_physical_mem.append(.{
                .start = @truncate(entry.addr),
                .end = end,
            });
        }
    }

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
