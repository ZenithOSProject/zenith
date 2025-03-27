const std = @import("std");
const Gdt = @This();

pub const AccessBits = packed struct {
    accessed: u1,
    read_write: u1,
    direction_conforming: u1,
    executable: u1,
    descriptor: u1,
    privilege: u2,
    present: u1,
};

pub const FlagBits = packed struct {
    reserved: u1 = 0,
    is_64bit: u1,
    is_32bit: u1,
    granularity: u1,
};

pub const Entry = packed struct {
    limit_low: u16,
    base_low: u24,
    access: AccessBits,
    limit_high: u4,
    flags: FlagBits,
    base_high: u8,

    pub fn init(base: u32, limit: u20, access: AccessBits, flags: FlagBits) Entry {
        std.debug.assert(flags.reserved == 0);
        return .{
            .limit_low = @truncate(limit),
            .base_low = @truncate(base),
            .access = access,
            .limit_high = @truncate(limit >> 16),
            .flags = .{
                .reserved = flags.reserved,
                .is_64bit = flags.is_64bit,
                .is_32bit = flags.is_32bit,
                .granularity = flags.granularity,
            },
            .base_high = @truncate(base >> 24),
        };
    }
};

pub const Tss = extern struct {
    prev_tss: u16,
    reserved1: u16,
    esp0: u32,
    ss0: u16,
    reserved2: u16,
    esp1: u32,
    ss1: u16,
    reserved3: u16,
    esp2: u32,
    ss2: u16,
    reserved4: u16,
    cr3: u32,
    eip: u32,
    eflags: u32,
    eax: u32,
    ecx: u32,
    edx: u32,
    ebx: u32,
    esp: u32,
    ebp: u32,
    esi: u32,
    edi: u32,
    es: u16,
    reserved5: u16,
    cs: u16,
    reserved6: u16,
    ss: u16,
    reserved7: u16,
    ds: u16,
    reserved8: u16,
    fs: u16,
    reserved9: u16,
    gs: u16,
    reserved10: u16,
    ldtr: u16,
    reserved11: u16,
    trap: u16,
    io_permissions_base_offset: u16,
};

pub const NULL_SEGMENT = AccessBits{
    .accessed = 0,
    .read_write = 0,
    .direction_conforming = 0,
    .executable = 0,
    .descriptor = 0,
    .privilege = 0,
    .present = 0,
};

pub const NULL_FLAGS = FlagBits{
    .is_64bit = 0,
    .is_32bit = 0,
    .granularity = 0,
};

pub const PAGING_32_BIT = FlagBits{
    .is_64bit = 0,
    .is_32bit = 1,
    .granularity = 1,
};

pub const KERNEL_SEGMENT_CODE = AccessBits{
    .accessed = 0,
    .read_write = 1,
    .direction_conforming = 0,
    .executable = 1,
    .descriptor = 1,
    .privilege = 0,
    .present = 1,
};

pub const KERNEL_SEGMENT_DATA = AccessBits{
    .accessed = 0,
    .read_write = 1,
    .direction_conforming = 0,
    .executable = 0,
    .descriptor = 1,
    .privilege = 0,
    .present = 1,
};

pub const USER_SEGMENT_CODE = AccessBits{
    .accessed = 0,
    .read_write = 1,
    .direction_conforming = 0,
    .executable = 1,
    .descriptor = 1,
    .privilege = 3,
    .present = 1,
};

pub const USER_SEGMENT_DATA = AccessBits{
    .accessed = 0,
    .read_write = 1,
    .direction_conforming = 0,
    .executable = 0,
    .descriptor = 1,
    .privilege = 3,
    .present = 1,
};

pub const TSS_SEGMENT: AccessBits = AccessBits{
    .accessed = 1,
    .read_write = 0,
    .direction_conforming = 0,
    .executable = 1,
    .descriptor = 0,
    .privilege = 0,
    .present = 1,
};

pub const Ptr = packed struct {
    limit: u16,
    base: u32,
};

pub const TSS_INDEX: u16 = 0x05;

pub const NULL_OFFSET: u16 = 0x00;
pub const KERNEL_CODE_OFFSET: u16 = 0x08;
pub const KERNEL_DATA_OFFSET: u16 = 0x10;
pub const USER_CODE_OFFSET: u16 = 0x18;
pub const USER_DATA_OFFSET: u16 = 0x20;
pub const TSS_OFFSET: u16 = 0x28;

pub var main_tss_entry: Tss = init: {
    var tss_temp = std.mem.zeroes(Tss);
    tss_temp.ss0 = KERNEL_DATA_OFFSET;
    tss_temp.io_permissions_base_offset = @sizeOf(Tss);
    break :init tss_temp;
};

pub var entries = [_]Entry{
    Entry.init(0, 0, NULL_SEGMENT, NULL_FLAGS),
    Entry.init(0, 0xFFFFF, KERNEL_SEGMENT_CODE, PAGING_32_BIT),
    Entry.init(0, 0xFFFFF, KERNEL_SEGMENT_DATA, PAGING_32_BIT),
    Entry.init(0, 0xFFFFF, USER_SEGMENT_CODE, PAGING_32_BIT),
    Entry.init(0, 0xFFFFF, USER_SEGMENT_DATA, PAGING_32_BIT),
    Entry.init(0, 0, NULL_SEGMENT, NULL_FLAGS),
};

pub var ptr = Ptr{
    .limit = getTableSize(&entries),
    .base = undefined,
};

pub fn init() void {
    entries[TSS_INDEX] = Entry.init(@intFromPtr(&main_tss_entry), @sizeOf(Tss) - 1, TSS_SEGMENT, NULL_FLAGS);

    ptr.base = @intFromPtr(&entries);
    lgdt(&ptr);

    ltr(TSS_OFFSET);
}

pub fn getTableSize(e: []Entry) u16 {
    return @sizeOf(Entry) * e.len - 1;
}

pub fn lgdt(gdt: *const Ptr) void {
    asm volatile ("lgdt (%%eax)"
        :
        : [gdt] "{eax}" (gdt),
    );

    asm volatile ("mov %%bx, %%ds"
        :
        : [KERNEL_DATA_OFFSET] "{bx}" (KERNEL_DATA_OFFSET),
    );

    asm volatile ("mov %%bx, %%es");
    asm volatile ("mov %%bx, %%fs");
    asm volatile ("mov %%bx, %%gs");
    asm volatile ("mov %%bx, %%ss");

    asm volatile (
        \\ljmp $0x08, $1f
        \\1:
    );
}

pub fn ltr(offset: u16) void {
    asm volatile ("ltr %%ax"
        :
        : [offset] "{ax}" (offset),
    );
}
