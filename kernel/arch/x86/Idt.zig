const Gdt = @import("Gdt.zig");
const Idt = @This();

pub const Entry = packed struct {
    base_low: u16,
    selector: u16,
    zero: u8 = 0,
    gate_type: u4,
    storage_segment: u1,
    privilege: u2,
    present: u1,
    base_high: u16,

    pub fn init(base: u32, selector: u16, gate_type: u4, privilege: u2) Entry {
        return .{
            .base_low = @truncate(base),
            .selector = selector,
            .gate_type = gate_type,
            .storage_segment = 0,
            .privilege = privilege,
            .present = 1,
            .base_high = @truncate(base >> 16),
        };
    }
};

pub const Ptr = packed struct {
    limit: u16,
    base: u32,
};

pub const Handler = *const fn () callconv(.Naked) void;

pub const TaskGates = struct {
    pub const BASE: u4 = 0x5;
    pub const INTERRUPT: u4 = 0xE;
    pub const TRAP: u4 = 0xF;
};

pub const Privileges = struct {
    pub const RING_0: u2 = 0x0;
    pub const RING_1: u2 = 0x1;
    pub const RING_2: u2 = 0x2;
    pub const RING_3: u2 = 0x3;
};

pub var entries: [256]Entry = .{Entry{
    .base_low = 0,
    .selector = 0,
    .zero = 0,
    .gate_type = 0,
    .storage_segment = 0,
    .privilege = 0,
    .present = 0,
    .base_high = 0,
}} ** 256;

pub var ptr = Ptr{
    .limit = getTableSize(&entries),
    .base = undefined,
};

pub fn init() void {
    ptr.base = @intFromPtr(&entries);
    lidt(&ptr);
}

pub fn isSet(i: u8) bool {
    return entries[i].present == 1;
}

pub fn setGate(i: u8, handler: Handler) error{AlreadyExists}!void {
    if (isSet(i)) return error.AlreadyExists;

    entries[i] = Entry.init(@intFromPtr(handler), Gdt.KERNEL_CODE_OFFSET, TaskGates.INTERRUPT, Privileges.RING_0);
}

pub fn getTableSize(e: []Entry) u16 {
    return @sizeOf(Entry) * e.len - 1;
}

pub fn lidt(idt: *const Ptr) void {
    asm volatile ("lidt (%%eax)"
        :
        : [idt] "{eax}" (idt),
    );
}
