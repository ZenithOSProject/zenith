const std = @import("std");
const VgaConsole = @This();

width: u8 = 80,
height: u8 = 25,
addr: usize = 0xB8000,
x: u8 = 0,
y: u8 = 0,

inline fn buffer(self: VgaConsole) []volatile u16 {
    return @as([*]volatile u16, @ptrFromInt(self.addr))[0..(self.width * self.height)];
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

pub fn clear(self: VgaConsole) void {
    @memset(self.buffer(), entry(' ', color(.black, .white) catch unreachable));
}

pub fn reset(self: *VgaConsole) void {
    self.clear();
    self.x = 0;
    self.y = 0;
}

pub fn putCharAt(self: VgaConsole, x: usize, y: usize, ch: u8, cv: u8) void {
    const i = y * self.width + x;
    self.buffer()[i] = entry(ch, cv);
}

pub fn putChar(self: *VgaConsole, ch: u8, cv: u8) void {
    self.putCharAt(self.x, self.y, ch, cv);
    self.x += 1;

    if (self.x == self.width) {
        self.x = 0;
        self.y += 1;

        if (self.y == self.height) {
            self.y = 0;
        }
    }
}

pub fn puts(self: *VgaConsole, str: []const u8) void {
    for (str) |c| self.putChar(c, color(.black, .white) catch unreachable);
}

pub const Writer = std.io.Writer(*VgaConsole, error{}, write);

pub fn write(self: *VgaConsole, buff: []const u8) error{}!usize {
    self.puts(buff);
    return buff.len;
}

pub fn writer(self: *VgaConsole) Writer {
    return .{ .context = self };
}
