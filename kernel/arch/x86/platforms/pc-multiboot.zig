const std = @import("std");
const builtin = @import("builtin");
const zenith = @import("zenith");
const Multiboot = zenith.boot.Multiboot;
const mem = zenith.mem;
const arch = zenith.arch.x86;
const pc = @import("pc.zig");

extern var kernel_paddr_offset: *u8;
extern var kernel_vaddr_offset: *u8;
extern var kernel_vaddr_end: *u8;

var multiboot: Multiboot.Header align(4) linksection(".multiboot") = Multiboot.Header.init(Multiboot.Header.Flags.ALIGN | Multiboot.Header.Flags.MEMINFO);

var stack_bytes: [64 * 1024]u8 align(16) linksection(".bss.stack") = undefined;

const KERNEL_PAGE_NUMBER = 0xC0000000 >> 22;
const KERNEL_NUM_PAGES = 1;

var boot_page_directory: [1024]u32 align(4096) linksection(".rodata.boot") = init: {
    @setEvalBranchQuota(1024);
    var dir: [1024]u32 = undefined;

    dir[0] = 0x00000083;

    var i = 0;
    var idx = 1;

    while (i < KERNEL_PAGE_NUMBER - 1) : ({
        i += 1;
        idx += 1;
    }) {
        dir[idx] = 0;
    }

    i = 0;
    while (i < KERNEL_NUM_PAGES) : ({
        i += 1;
        idx += 1;
    }) {
        dir[idx] = 0x00000083 | (i << 22);
    }
    i = 0;
    while (i < 1024 - KERNEL_PAGE_NUMBER - KERNEL_NUM_PAGES) : ({
        i += 1;
        idx += 1;
    }) {
        dir[idx] = 0;
    }
    break :init dir;
};

fn _start() linksection(".text.boot") callconv(.Naked) noreturn {
    asm volatile (
        \\mov %[boot_page_directory], %%ecx
        \\mov %%ecx, %%cr3
        \\
        \\mov %%cr4, %%ecx
        \\or $0x00000010, %%ecx
        \\mov %%ecx, %%cr4
        \\
        \\mov %%cr0, %%ecx
        \\or $0x80000000, %%ecx
        \\mov %%ecx, %%cr0
        \\
        \\jmp %[_start_higher:P]
        :
        : [boot_page_directory] "r" (&boot_page_directory),
          [_start_higher] "X" (&_start_higher),
    );
}

fn _start_higher() callconv(.C) noreturn {
    asm volatile (
        \\invlpg (0)
        \\
        \\movl %[stack_top], %%esp
        \\movl %%esp, %%ebp
        \\call %[_start_bootstrap:P]
        :
        : [stack_top] "i" (@as([*]align(16) u8, @ptrCast(&stack_bytes)) + @sizeOf(@TypeOf(stack_bytes))),
          [_start_bootstrap] "X" (&_start_bootstrap),
    );

    @breakpoint();
    unreachable;
}

fn _start_bootstrap() callconv(.C) void {
    const mb_info_addr = asm (
        \\mov %%ebx, %[res]
        : [res] "=r" (-> usize),
    ) + @intFromPtr(&kernel_paddr_offset);

    mem.ADDR_OFFSET = @intFromPtr(&kernel_paddr_offset);

    arch.bootstrap();

    const kmem_virt = mem.Range{
        .start = @intFromPtr(&kernel_vaddr_offset),
        .end = @intFromPtr(&kernel_vaddr_end),
    };

    Multiboot.info = @ptrFromInt(mb_info_addr);

    var mem_profile = Multiboot.initMem(pc.kernel_alloc, kmem_virt, .{
        .start = mem.virtToPhys(kmem_virt.start),
        .end = mem.virtToPhys(kmem_virt.end),
    }) catch |err| std.debug.panic("Failed to initialize memory from multiboot: {s}", .{
        @errorName(err),
    });
    defer mem_profile.deinit();
    pc.bootstrap(mem_profile);

    @import("root").main();

    @breakpoint();
    while (true) @trap();
}

pub const panic = pc.panic;
pub const logFn = pc.logFn;
pub const queryPageSize = pc.queryPageSize;
pub const page_size_min = pc.page_size_min;
pub const page_size_max = pc.page_size_max;

comptime {
    @export(&multiboot, .{
        .name = "multiboot",
    });

    @export(&_start, .{
        .name = "_start",
    });
}
