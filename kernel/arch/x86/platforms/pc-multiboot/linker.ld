ENTRY(_start)

kernel_paddr_offset = 0xC0000000;
kernel_vaddr_offset = 0xC0100000;
 
SECTIONS {
  . = 1M;
  kernel_paddr_start = .;

  .rodata.boot : {
    KEEP(*(.multiboot))
    KEEP(*(.rodata.boot))
  }

  .text.boot : {
    *(.text.boot)
  }

  . += kernel_paddr_offset;

  .text ALIGN(4K) : AT(ADDR(.text) - kernel_paddr_offset) {
    *(.text)
  }

  .rodata ALIGN(4K) : AT(ADDR(.rodata) - kernel_paddr_offset) {
    *(.rodata)
  }
 
  .data ALIGN(4K) : AT(ADDR(.data) - kernel_paddr_offset) {
    *(.data)
  }
 
  .bss ALIGN(4K) : AT(ADDR(.bss) - kernel_paddr_offset) {
    *(COMMON)
    *(.bss)
  }

  .bss.stack ALIGN(4K) : AT(ADDR(.bss.stack) - kernel_paddr_offset) {
    kernel_stack_start = .;
    KEEP(*(.bss.stack))
    kernel_stack_end = .;
  }

  kernel_vaddr_end = .;
  kernel_paddr_end = . - kernel_paddr_offset;
}
