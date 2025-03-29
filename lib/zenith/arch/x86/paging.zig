const std = @import("std");
const Allocator = std.mem.Allocator;
const cpu = @import("Cpu.zig");
const io = @import("io.zig");
const isr = @import("isr.zig");
const mem = @import("../../mem.zig");
const log = std.log.scoped(.@"arch.x86.paging");

const ENTRIES_PER_DIRECTORY: u32 = 1024;
const ENTRIES_PER_TABLE: u32 = 1024;
const PAGES_PER_DIR_ENTRY: u32 = 1024;
const PAGES_PER_DIR: u32 = ENTRIES_PER_DIRECTORY * PAGES_PER_DIR_ENTRY;

pub const Directory = extern struct {
    entries: [ENTRIES_PER_DIRECTORY]DirectoryEntry,
    tables: [ENTRIES_PER_DIRECTORY]?*Table,

    pub fn copy(self: *const Directory) Directory {
        return self.*;
    }
};

pub const Table = extern struct {
    entries: [ENTRIES_PER_TABLE]TableEntry,
};

pub const TableEntry = u32;
pub const DirectoryEntry = u32;

pub const PAGE_SIZE_4MB: usize = 0x400000;
pub const PAGE_SIZE_4KB: usize = PAGE_SIZE_4MB / 1024;

pub var kernel_directory: Directory align(@as(u29, @truncate(PAGE_SIZE_4KB))) = Directory{ .entries = [_]DirectoryEntry{0} ** ENTRIES_PER_DIRECTORY, .tables = [_]?*Table{null} ** ENTRIES_PER_DIRECTORY };

const DENTRY_PRESENT: u32 = 0x1;
const DENTRY_WRITABLE: u32 = 0x2;
const DENTRY_USER: u32 = 0x4;
const DENTRY_WRITE_THROUGH: u32 = 0x8;
const DENTRY_CACHE_DISABLED: u32 = 0x10;
const DENTRY_ACCESSED: u32 = 0x20;
const DENTRY_ZERO: u32 = 0x40;
const DENTRY_4MB_PAGES: u32 = 0x80;
const DENTRY_IGNORED: u32 = 0x100;
const DENTRY_AVAILABLE: u32 = 0xE00;
const DENTRY_PAGE_ADDR: u32 = 0xFFFFF000;

const TENTRY_PRESENT: u32 = 0x1;
const TENTRY_WRITABLE: u32 = 0x2;
const TENTRY_USER: u32 = 0x4;
const TENTRY_WRITE_THROUGH: u32 = 0x8;
const TENTRY_CACHE_DISABLED: u32 = 0x10;
const TENTRY_ACCESSED: u32 = 0x20;
const TENTRY_DIRTY: u32 = 0x40;
const TENTRY_ZERO: u32 = 0x80;
const TENTRY_GLOBAL: u32 = 0x100;
const TENTRY_AVAILABLE: u32 = 0xE00;
const TENTRY_PAGE_ADDR: u32 = 0xFFFFF000;

fn pageFault(state: *cpu.State) u32 {
    const cr0 = asm volatile ("mov %%cr0, %[cr0]"
        : [cr0] "=r" (-> u32),
    );
    const cr2 = asm volatile ("mov %%cr2, %[cr2]"
        : [cr2] "=r" (-> u32),
    );
    const cr3 = asm volatile ("mov %%cr3, %[cr3]"
        : [cr3] "=r" (-> u32),
    );
    const cr4 = asm volatile ("mov %%cr4, %[cr4]"
        : [cr4] "=r" (-> u32),
    );

    std.debug.panicExtra(state.eip, "Page fault! State: {}, CR0: 0x{x}, CR2: 0x{x}, CR3: 0x{x}, CR4: 0x{x}", .{ state, cr0, cr2, cr3, cr4 });
}

pub fn init(_: *const mem.Profile) void {
    isr.set(14, pageFault) catch |e| std.debug.panic("Failed to set ISR: {s}", .{@errorName(e)});

    const dir_physaddr = @intFromPtr(mem.virtToPhys(&kernel_directory));
    asm volatile (
        \\cli
        \\mov %[addr], %%cr3
        :
        : [addr] "{eax}" (dir_physaddr),
    );
}

inline fn virtToDirEntryIdx(virt: usize) usize {
    return virt / (std.heap.pageSize() * 1024);
}

inline fn virtToTableEntryIdx(virt: usize) usize {
    return (virt / std.heap.pageSize()) % ENTRIES_PER_TABLE;
}

inline fn setAttribute(val: *align(1) u32, attr: u32) void {
    val.* |= attr;
}

inline fn clearAttribute(val: *align(1) u32, attr: u32) void {
    val.* &= ~attr;
}

fn mapTableEntry(dir: *const Directory, entry: *align(1) TableEntry, virt_addr: usize, phys_addr: usize, attrs: mem.virt.Attributes) mem.virt.MapperError!void {
    if (!std.mem.isAligned(phys_addr, std.heap.pageSize())) {
        return mem.virt.MapperError.MisalignedPhysicalAddress;
    }
    setAttribute(entry, TENTRY_PRESENT);
    if (attrs.writable) {
        setAttribute(entry, TENTRY_WRITABLE);
    } else {
        clearAttribute(entry, TENTRY_WRITABLE);
    }
    if (attrs.kernel) {
        clearAttribute(entry, TENTRY_USER);
    } else {
        setAttribute(entry, TENTRY_USER);
    }

    if (attrs.cachable) {
        clearAttribute(entry, TENTRY_WRITE_THROUGH);
        clearAttribute(entry, TENTRY_CACHE_DISABLED);
    } else {
        setAttribute(entry, TENTRY_WRITE_THROUGH);
        setAttribute(entry, TENTRY_CACHE_DISABLED);
    }

    clearAttribute(entry, TENTRY_GLOBAL);
    setAttribute(entry, TENTRY_PAGE_ADDR & phys_addr);
    if (dir == &kernel_directory) {
        asm volatile ("invlpg (%[addr])"
            :
            : [addr] "r" (virt_addr),
            : "memory"
        );
    }
}

fn unmapDirEntry(dir: *Directory, virt_start: usize, virt_end: usize, _: Allocator) mem.virt.MapperError!void {
    const entry = virtToDirEntryIdx(virt_start);
    const table = dir.tables[entry] orelse return mem.virt.MapperError.NotMapped;
    var addr = virt_start;
    while (addr < virt_end) : (addr += std.heap.pageSize()) {
        const table_entry = &table.entries[virtToTableEntryIdx(addr)];
        if (table_entry.* & TENTRY_PRESENT != 0) {
            clearAttribute(table_entry, TENTRY_PRESENT);
            if (dir == &kernel_directory) {
                asm volatile ("invlpg (%[addr])"
                    :
                    : [addr] "r" (addr),
                    : "memory"
                );
            }
        } else {
            return mem.virt.MapperError.NotMapped;
        }
    }
}

fn mapDirEntry(dir: *Directory, virt_start: usize, virt_end: usize, phys_start: usize, phys_end: usize, attrs: mem.virt.Attributes, allocator: Allocator) (mem.virt.MapperError || Allocator.Error)!void {
    if (phys_start > phys_end) {
        return mem.virt.MapperError.InvalidPhysicalAddress;
    }
    if (virt_start > virt_end) {
        return mem.virt.MapperError.InvalidVirtualAddress;
    }
    if (phys_end - phys_start != virt_end - virt_start) {
        return mem.virt.MapperError.AddressMismatch;
    }
    if (!std.mem.isAligned(phys_start, std.heap.pageSize()) or !std.mem.isAligned(phys_end, std.heap.pageSize())) {
        return mem.virt.MapperError.MisalignedPhysicalAddress;
    }
    if (!std.mem.isAligned(virt_start, std.heap.pageSize()) or !std.mem.isAligned(virt_end, std.heap.pageSize())) {
        return mem.virt.MapperError.MisalignedVirtualAddress;
    }

    const entry = virtToDirEntryIdx(virt_start);
    const dir_entry = &dir.entries[entry];

    var table: *Table = undefined;
    if (dir.tables[entry]) |tbl| {
        table = tbl;
    } else {
        table = &(try allocator.alignedAlloc(Table, @as(u29, @truncate(std.heap.pageSize())), 1))[0];
        @memset(@as([*]u8, @ptrCast(table))[0..@sizeOf(Table)], 0);
        const table_phys_addr = mem.virt.kernel_vmm.virtToPhys(@intFromPtr(table)) catch |e| std.debug.panic("Failed getting the physical address for a page table: {}", .{e});
        dir_entry.* |= DENTRY_PAGE_ADDR & table_phys_addr;
        dir.tables[entry] = table;
    }

    setAttribute(dir_entry, DENTRY_PRESENT);
    setAttribute(dir_entry, DENTRY_WRITE_THROUGH);
    clearAttribute(dir_entry, DENTRY_4MB_PAGES);

    if (attrs.writable) {
        setAttribute(dir_entry, DENTRY_WRITABLE);
    } else {
        clearAttribute(dir_entry, DENTRY_WRITABLE);
    }

    if (attrs.kernel) {
        clearAttribute(dir_entry, DENTRY_USER);
    } else {
        setAttribute(dir_entry, DENTRY_USER);
    }

    if (attrs.cachable) {
        clearAttribute(dir_entry, DENTRY_CACHE_DISABLED);
    } else {
        setAttribute(dir_entry, DENTRY_CACHE_DISABLED);
    }

    var virt = virt_start;
    var phys = phys_start;
    var tentry = virtToTableEntryIdx(virt);
    while (virt < virt_end) : ({
        virt += std.heap.pageSize();
        phys += std.heap.pageSize();
        tentry += 1;
    }) {
        try mapTableEntry(dir, &table.entries[tentry], virt, phys, attrs);
    }
}

pub fn map(
    virtual_start: usize,
    virtual_end: usize,
    phys_start: usize,
    phys_end: usize,
    attrs: mem.virt.Attributes,
    allocator: Allocator,
    dir: *Directory,
) (Allocator.Error || mem.virt.MapperError)!void {
    const page_size_mb = std.heap.pageSize() * 1024;
    var virt_addr = virtual_start;
    var phys_addr = phys_start;
    var virt_next = @min(virtual_end, std.mem.alignBackward(usize, virt_addr, page_size_mb) + page_size_mb);
    var phys_next = @min(phys_end, std.mem.alignBackward(usize, phys_addr, page_size_mb) + page_size_mb);
    var entry_idx = virtToDirEntryIdx(virt_addr);
    while (entry_idx < ENTRIES_PER_DIRECTORY and virt_addr < virtual_end) : ({
        virt_addr = virt_next;
        phys_addr = phys_next;
        virt_next = @min(virtual_end, virt_next + page_size_mb);
        phys_next = @min(phys_end, phys_next + page_size_mb);
        entry_idx += 1;
    }) {
        try mapDirEntry(dir, virt_addr, virt_next, phys_addr, phys_next, attrs, allocator);
    }

    log.info("Mapped {x} - {x} / {x} - {x} ({}) in {x}", .{
        virtual_start,
        virtual_end,
        phys_start,
        phys_end,
        attrs,
        @intFromPtr(dir),
    });
}

pub fn unmap(virtual_start: usize, virtual_end: usize, allocator: Allocator, dir: *Directory) mem.virt.MapperError!void {
    const page_size_mb = std.heap.pageSize() * 1024;
    var virt_addr = virtual_start;
    var virt_next = @min(virtual_end, std.mem.alignBackward(usize, virt_addr, page_size_mb) + page_size_mb);
    var entry_idx = virtToDirEntryIdx(virt_addr);
    while (entry_idx < ENTRIES_PER_DIRECTORY and virt_addr < virtual_end) : ({
        virt_addr = virt_next;
        virt_next = @min(virtual_end, virt_next + page_size_mb);
        entry_idx += 1;
    }) {
        try unmapDirEntry(dir, virt_addr, virt_next, allocator);
        if (std.mem.isAligned(virt_addr, page_size_mb) and virt_next - virt_addr >= page_size_mb) {
            clearAttribute(&dir.entries[entry_idx], DENTRY_PRESENT);

            const table = dir.tables[entry_idx] orelse return mem.virt.MapperError.NotMapped;
            const table_free = @as([*]Table, @ptrCast(table))[0..1];
            allocator.free(table_free);
        }
    }
}
