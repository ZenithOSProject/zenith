const std = @import("std");
const Idt = @import("Idt.zig");
const Cpu = @import("Cpu.zig");
const Pic = @import("Pic.zig");
const interrupts = @import("interrupts.zig");

pub const OFFSET = 32;

pub const Handler = *const fn (*Cpu.State) usize;
var handlers: [16]?Handler = [_]?Handler{null} ** 16;

pub fn handler(state: *Cpu.State) usize {
    if (state.int_num < OFFSET) {
        std.debug.panic("Invalid IRQ {}: out of range", .{state.int_num - OFFSET});
    }

    const irq: u8 = @truncate(state.int_num - OFFSET);
    var ret_esp = @intFromPtr(state);

    if (isValid(irq)) {
        if (handlers[irq]) |callback| {
            if (!Pic.isSpuriousIrq(irq)) {
                ret_esp = callback(state);
                Pic.sendEndOfInterrupt(irq);
            }
        }
    }
    return ret_esp;
}

pub fn init() void {
    comptime var i = 0;
    inline while (i < 16) : (i += 1) {
        Idt.setGate(i + OFFSET, interrupts.getStub(i + OFFSET)) catch unreachable;
    }
}

pub fn isValid(i: u32) bool {
    return i < handlers.len;
}

pub fn set(i: u32, callback: Handler) error{ AlreadyExists, Invalid }!void {
    if (!isValid(i)) {
        return error.Invalid;
    }

    if (handlers[i]) |_| {
        return error.AlreadyExists;
    }

    handlers[i] = callback;
}
