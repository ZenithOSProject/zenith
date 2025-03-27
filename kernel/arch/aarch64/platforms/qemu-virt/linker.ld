ENTRY(_start)
SECTIONS {
    . = 0x40100000;
    .text : { *(.text) }
    .data : { *(.data) }
    .bss : { *(.bss COMMON) }
}
