const std = @import("std");
const SerialConsole = @This();

addr: usize = 0x9000000,

pub fn writeByte(self: SerialConsole, ch: u8) void {
    const ptr: [*]volatile u8 = @ptrFromInt(self.addr);
    ptr[0] = ch;
}

pub fn write(self: SerialConsole, buff: []const u8) error{}!usize {
    for (buff) |ch| self.writeByte(ch);
    return buff.len;
}

pub const Writer = std.io.Writer(SerialConsole, error{}, write);

pub fn writer(self: SerialConsole) Writer {
    return .{ .context = self };
}
