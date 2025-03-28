const std = @import("std");
const arch = @import("../main.zig").arch;
const platform = @import("../main.zig").platform;
const mem = @import("../mem.zig");

pub const uint8_t = u8;
pub const uint16_t = c_ushort;
pub const uint32_t = c_uint;
pub const int32_t = c_int;
pub const uint64_t = c_ulonglong;

pub const magic: i32 = 0x1BADB002;

pub const Header = extern struct {
    magic: uint32_t = MAGIC,
    flags: uint32_t,
    checksum: int32_t,

    pub fn init(flags: uint32_t) Header {
        return .{
            .flags = flags,
            .checksum = -(@as(int32_t, @intCast(MAGIC)) + @as(int32_t, @intCast(flags))),
        };
    }

    pub const MAGIC = 0x1BADB002;
    pub const Flags = struct {
        pub const ALIGN = 1 << 0;
        pub const MEMINFO = 1 << 1;
    };
};

pub const Info = extern struct {
    flags: uint32_t,
    mem_lower: uint32_t,
    mem_upper: uint32_t,
    boot_device: uint32_t,
    cmdline: uint32_t,
    mods_count: uint32_t,
    mods_addr: uint32_t,
    binary: extern union {
        aout: extern struct {
            tabsize: uint32_t,
            strsize: uint32_t,
            addr: uint32_t,
            reserved: uint32_t,
        },
        elf: extern struct {
            num: uint32_t,
            size: uint32_t,
            addr: uint32_t,
            shndx: uint32_t,
        },
    },
    mmap_len: uint32_t,
    mmap_addr: uint32_t,
    drives_len: uint32_t,
    drives_addr: uint32_t,
    cfgtbl: uint32_t,
    bootloader_name: uint32_t,
    apm_table: uint32_t,
};

pub const MemoryMap = packed struct {
    size: uint32_t,
    addr: uint64_t,
    len: uint64_t,
    type: uint32_t,
};

pub const ModuleList = packed struct {
    mod_start: uint32_t,
    mod_end: uint32_t,
    cmdline: uint32_t,
    pad: uint32_t,
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
            //FIXME: getting all the wrong values
            //const end: usize = if (entry.addr > std.math.maxInt(usize) - entry.len) std.math.maxInt(usize) else @truncate(entry.addr + entry.len);
            //try reserved_physical_mem.append(.{
            //    .start = @truncate(entry.addr),
            //    .end = end,
            //});
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
