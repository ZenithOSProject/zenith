const std = @import("std");
const zenith = @import("zenith");
const pio = zenith.arch.x86.io.port;
const mem = zenith.mem;
const VgaConsole = @This();

fg: std.io.tty.Color,
bg: std.io.tty.Color,
x: u8,
y: u8,

pub fn buffer(self: *VgaConsole) []volatile u16 {
    _ = self;
    return @as([*]volatile u16, @ptrFromInt(0xB8000 + mem.ADDR_OFFSET))[0..(80 * 25)];
}

fn colorField(v: std.io.tty.Color) error{IncompatibleColor}!u8 {
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

fn color(bg: std.io.tty.Color, fg: std.io.tty.Color) error{IncompatibleColor}!u8 {
    return try colorField(fg) | (try colorField(bg) << 4);
}

fn entry(ch: u8, cv: u8) u16 {
    return ch | (@as(u16, @intCast(cv)) << 8);
}

fn moveCursor(width: u8, x: u8, y: u8) void {
    const pos = @as(u16, y) * @as(u16, width) + @as(u16, x);

    const pos_upper = (pos >> 8) & 0x00FF;
    const pos_lower = pos & 0x00FF;

    pio.out(0x3d4, @as(u8, 0x0f));
    pio.out(0x3d5, @as(u8, @truncate(pos_lower)));

    pio.out(0x3d4, @as(u8, 0xe));
    pio.out(0x3d5, @as(u8, @truncate(pos_upper)));
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
    var buff = self.buffer();

    const i = @min(buff.len - 1, y * 80 + x);
    buff[i] = entry(ch, cv);
}

pub fn writeByte(self: *VgaConsole, ch: u8) error{IncompatibleColor}!void {
    const cv = try color(self.bg, self.fg);

    defer {
        self.x = self.x % 80;
        self.y = self.y % 25;
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
