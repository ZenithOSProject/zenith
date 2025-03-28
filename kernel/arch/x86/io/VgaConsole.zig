const std = @import("std");
const pio = @import("port.zig");
const VgaConsole = @This();

fg: std.io.tty.Color,
bg: std.io.tty.Color,
x: u8,
y: u8,

inline fn buffer(self: *VgaConsole) []volatile u16 {
    _ = self;
    return @as([*]volatile u16, @ptrFromInt(0xB8000))[0..(80 * 25)];
}

inline fn colorField(v: std.io.tty.Color) error{IncompatibleColor}!u8 {
    return switch (v) {
        .black => 0,
        .red, .yellow => 4,
        .green => 2,
        .blue => 1,
        .magenta => 5,
        .cyan => 3,
        .white => 15,
        .bright_black => 7,
        .bright_red, .bright_yellow => 12,
        .bright_green => 10,
        .bright_blue => 9,
        .bright_magenta => 13,
        .bright_cyan => 11,
        else => error.IncompatibleColor,
    };
}

inline fn color(bg: std.io.tty.Color, fg: std.io.tty.Color) error{IncompatibleColor}!u8 {
    return try colorField(fg) | (try colorField(bg) << 4);
}

inline fn entry(ch: u8, cv: u8) u16 {
    return ch | (@as(u16, @intCast(cv)) << 8);
}

fn moveCursor(width: u8, x: u8, y: u8) void {
    const pos = @as(u16, y * width + x);

    pio.out(0x3d4, @as(u8, 0x0f));
    pio.out(0x3d5, @as(u8, @truncate(pos & 0xff)));

    pio.out(0x3d4, @as(u8, 0xe));
    pio.out(0x3d5, @as(u8, @truncate((pos >> 8) & 0xff)));
}

pub fn init() VgaConsole {
    return .{
        .bg = .black,
        .fg = .white,
        .x = 0,
        .y = 0,
    };
}

pub fn clear(self: *VgaConsole) void {
    @memset(self.buffer(), entry(' ', color(self.bg, self.fg) catch unreachable));
}

pub fn reset(self: *VgaConsole) void {
    self.bg = .black;
    self.fg = .white;

    self.clear();

    self.x = 0;
    self.y = 0;
    moveCursor(50, self.x, self.y);
}

pub fn putCharAt(self: *VgaConsole, x: usize, y: usize, ch: u8, cv: u8) void {
    const i = y * 80 + x;
    self.buffer()[i] = entry(ch, cv);
}

pub fn writeByte(self: *VgaConsole, ch: u8) error{IncompatibleColor}!void {
    const cv = try color(self.bg, self.fg);

    defer {
        if (self.x == 80) {
            self.x = 0;
            self.y += 1;

            if (self.y == 25) {
                self.y = 0;
            }
        }

        moveCursor(80, self.x, self.y);
    }

    switch (ch) {
        '\n' => {
            self.x = 0;
            self.y += 1;
        },
        '\r' => {
            self.y = 0;
        },
        '\t' => {
            self.x = 4;
        },
        else => {
            self.putCharAt(self.x, self.y, ch, cv);
            self.x += 1;
        },
    }
}

pub const Writer = std.io.Writer(*VgaConsole, error{IncompatibleColor}, write);

pub fn write(self: *VgaConsole, buff: []const u8) error{IncompatibleColor}!usize {
    for (buff) |c| try self.writeByte(c);
    return buff.len;
}

pub fn writer(self: *VgaConsole) Writer {
    return .{ .context = self };
}
