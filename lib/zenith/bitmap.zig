const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Bitmap(comptime EntryCount: ?usize, comptime T: type) type {
    return struct {
        const Self = @This();
        const static = EntryCount != null;

        pub const EntryPerMap = @typeInfo(T).int.bits;
        pub const Full = std.math.maxInt(T);
        pub const IndexType = std.meta.Int(.unsigned, std.math.log2(std.math.ceilPowerOfTwo(u16, EntryPerMap) catch unreachable));

        bitmap_count: usize,
        entry_count: usize,
        bitmaps: if (static) [std.mem.alignForward(EntryCount.?, EntryPerMap) / EntryPerMap]T else []T,
        free_count: usize,
        allocator: if (static) ?Allocator else Allocator,

        fn indexToBit(idx: usize) T {
            return @as(T, 1) << @as(IndexType, @intCast(idx % EntryPerMap));
        }

        pub fn init(num: if (static) ?usize else usize, allocator: if (static) ?Allocator else Allocator) !Self {
            if (static) {
                const n = std.mem.alignForward(usize, EntryCount.?, EntryPerMap) / EntryPerMap;
                return .{
                    .bitmap_count = n,
                    .entry_count = EntryCount.?,
                    .bitmaps = [_]T{0} ** (std.mem.alignForward(usize, EntryCount.?, EntryPerMap) / EntryPerMap),
                    .free_count = EntryCount.?,
                    .allocator = null,
                };
            } else {
                const n = std.mem.alignForward(usize, num, EntryPerMap) / EntryPerMap;
                const self = Self{
                    .bitmap_count = n,
                    .entry_count = num,
                    .bitmaps = try allocator.alloc(T, n),
                    .free_count = num,
                    .allocator = allocator,
                };
                for (self.bitmaps) |*bmp| {
                    bmp.* = 0;
                }
                return self;
            }
        }

        pub fn clone(self: *const Self) Allocator.Error!Self {
            var copy = try init(self.entry_count, self.allocator);
            var i: usize = 0;
            while (i < copy.entry_count) : (i += 1) {
                if (self.isSet(i) catch unreachable) {
                    copy.setEntry(i) catch unreachable;
                }
            }
            return copy;
        }

        pub fn deinit(self: *Self) void {
            if (!static) self.allocator.free(self.bitmaps);
        }

        pub fn setEntry(self: *Self, idx: usize) error{OutOfBounds}!void {
            if (idx >= self.entry_count) {
                return error.OutOfBounds;
            }
            if (!try self.isSet(idx)) {
                const bit = indexToBit(idx);
                self.bitmaps[idx / EntryPerMap] |= bit;
                self.free_count -= 1;
            }
        }

        pub fn clearEntry(self: *Self, idx: usize) error{OutOfBounds}!void {
            if (idx >= self.entry_count) {
                return error.OutOfBounds;
            }
            if (try self.isSet(idx)) {
                const bit = indexToBit(idx);
                self.bitmaps[idx / EntryPerMap] &= ~bit;
                self.free_count += 1;
            }
        }

        pub fn setFirstFree(self: *Self) ?usize {
            if (self.free_count == 0) {
                return null;
            }
            for (self.bitmaps, 0..) |*bmp, i| {
                if (bmp.* == Full) {
                    continue;
                }
                const bit: IndexType = @truncate(@as(T, @ctz(~bmp.*)));
                const idx = bit + i * EntryPerMap;
                self.setEntry(idx) catch return null;
                return idx;
            }
            return null;
        }

        pub fn isSet(self: *const Self, idx: usize) error{OutOfBounds}!bool {
            if (idx >= self.entry_count) {
                return error.OutOfBounds;
            }
            return (self.bitmaps[idx / EntryPerMap] & indexToBit(idx)) != 0;
        }

        pub fn setContiguous(self: *Self, num: usize, from: ?usize) ?usize {
            if (num > self.free_count) {
                return null;
            }

            var count: usize = 0;
            var start: ?usize = from;
            var i: usize = if (from) |f| f / EntryPerMap else 0;
            var bit: IndexType = if (from) |f| @as(IndexType, @truncate(f % EntryPerMap)) else 0;

            while (i < self.bitmaps.len) : ({
                i += 1;
                bit = 0;
            }) {
                const bmp = self.bitmaps[i];

                while (true) {
                    const entry = bit + i * EntryPerMap;
                    if (entry >= self.entry_count) return null;

                    if ((bmp & @as(T, 1) << bit) != 0) {
                        count = 0;
                        start = null;
                        if (from) |_| return null;
                    } else {
                        count += 1;
                        if (start == null) {
                            start = entry;
                        }
                        if (count == num) {
                            break;
                        }
                    }

                    if (bit < EntryPerMap - 1) {
                        bit += 1;
                    } else break;
                }

                if (count == num) break;
            }

            if (count == num) {
                if (start) |start_entry| {
                    var j: usize = 0;
                    while (j < num) : (j += 1) {
                        self.setEntry(start_entry + j) catch unreachable;
                    }
                    return start_entry;
                }
            }
            return null;
        }
    };
}
