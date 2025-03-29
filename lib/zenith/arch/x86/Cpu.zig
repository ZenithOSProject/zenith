pub const State = packed struct {
    cr3: usize,
    gs: u32,
    fs: u32,
    es: u32,
    ds: u32,

    edi: u32,
    esi: u32,
    ebp: u32,
    esp: u32,

    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,

    int_num: u32,
    error_code: u32,

    eip: u32,
    cs: u32,
    eflags: u32,
    user_esp: u32,
    user_ss: u32,
};
