pub const magic: i32 = 0x1BADB002;

pub const Header = extern struct {
    magic: i32 = magic,
    flags: Flags,
    checksum: i32,
    header_addr: i32 = 0,
    load_addr: i32 = 0,
    load_end_addr: i32 = 0,
    bss_end_addr: i32 = 0,
    entry_addr: i32 = 0,
    mode_type: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    depth: i32 = 0,

    pub const Flags = packed struct(i32) {
        pg_align: bool = false,
        mem_info: bool = false,
        video_mode: bool = false,
        aout_kludge: bool = false,
        padding: i28 = 0,
    };

    pub fn init(flags: Flags) Header {
        return .{
            .flags = flags,
            .checksum = -(magic + @as(i32, @bitCast(flags))),
        };
    }
};
