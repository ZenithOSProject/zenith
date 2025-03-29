const builtin = @import("builtin");
const std = @import("std");
const limine = @import("limine");

export var start_marker: limine.RequestsStartMarker linksection(".limine_requests_start") = .{};
export var end_marker: limine.RequestsEndMarker linksection(".limine_requests_end") = .{};

export var base_revision: limine.BaseRevision linksection(".limine_requests") = .init(3);
export var mmap_request: limine.MemoryMapRequest linksection(".limine_requests") = .{};
export var dtb_request: limine.DtbRequest linksection(".limine_requests") = .{};

export fn _start() noreturn {
    if (!base_revision.isSupported()) {
        @panic("Base revision not supported");
    }

    while (true) asm volatile ("wfi");
}
