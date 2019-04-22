#include <asm.h>

# Start the CPU: switch to 32-bit protected mode, jump into C.
# The BIOS loads this code from the first sector of the hard disk into
# memory at physical address 0x7c00 and starts executing in real mode
# with %cs=0 %ip=7c00.

.set PROT_MODE_CSEG,        0x8                     # kernel code segment selector
.set PROT_MODE_DSEG,        0x10                    # kernel data segment selector
.set CR0_PE_ON,             0x1                     # protected mode enable flag

# start address should be 0:7c00, in real mode, the beginning address of the running bootloader
.globl start
start:
.code16                                             # Assemble for 16-bit mode
    cli                                             # Disable interrupts
    cld                                             # String operations increment

    # Set up the important data segment registers (DS, ES, SS).
    xorw %ax, %ax                                   # Segment number zero
    movw %ax, %ds                                   # -> Data Segment
    movw %ax, %es                                   # -> Extra Segment
    movw %ax, %ss                                   # -> Stack Segment

    # Enable A20:
    #  For backwards compatibility with the earliest PCs, physical
    #  address line 20 is tied low, so that addresses higher than
    #  1MB wrap around to zero by default. This code undoes this.
seta20.1:
    inb $0x64, %al                                  # Wait for not busy(8042 input buffer empty).
    testb $0x2, %al
    jnz seta20.1

    movb $0xd1, %al                                 # 0xd1 -> port 0x64
    outb %al, $0x64                                 # 0xd1 means: write data to 8042's P2 port

seta20.2:
    inb $0x64, %al                                  # Wait for not busy(8042 input buffer empty).
    testb $0x2, %al
    jnz seta20.2

    movb $0xdf, %al                                 # 0xdf -> port 0x60
    outb %al, $0x60                                 # 0xdf = 11011111, means set P2's A20 bit(the 1 bit) to 1

    # Switch from real to protected mode, using a bootstrap GDT
    # and segment translation that makes virtual addresses
    # identical to physical addresses, so that the
    # effective memory map does not change during the switch.
    lgdt gdtdesc
    movl %cr0, %eax
    orl $CR0_PE_ON, %eax
    movl %eax, %cr0

    # Jump to next instruction, but in 32-bit code segment.
    # Switches processor into 32-bit mode.
    ljmp $PROT_MODE_CSEG, $protcseg

.code32                                             # Assemble for 32-bit mode
protcseg:
    # Set up the protected-mode data segment registers
    movw $PROT_MODE_DSEG, %ax                       # Our data segment selector
    movw %ax, %ds                                   # -> DS: Data Segment
    movw %ax, %es                                   # -> ES: Extra Segment
    movw %ax, %fs                                   # -> FS
    movw %ax, %gs                                   # -> GS
    movw %ax, %ss                                   # -> SS: Stack Segment

    # Set up the stack pointer and call into C. The stack region is from 0--start(0x7c00)
    #系统程序栈的起始
    movl $0x0, %ebp
    #start为7c00，boot程序的栈段就是从0x7c00，在这里面增长减少
    movl $start, %esp
    #栈底初始化为0x7c00
    #call指令，会把cs和ip入栈，执行完后，esp-4，变成0x7bfc，并且此处的4个字节为7c4f，即返回地址，call的下一条指令地址
    #但此处不应该返回
    call bootmain
    #call之后，在执行bootmain函数之前，编译器，会把原始ebp入栈，0x0，然后ebp为新的栈顶，即0x7bfc-4=0x7bf8，然后就开始执行函数代码了

    # If bootmain returns (it shouldn't), loop.
spin:
    jmp spin

# Bootstrap GDT
.p2align 2                                          # force 4 byte alignment
gdt: #段描述符表 0x7c54， 一共24个字节
    SEG_NULLASM            #一个段描述符8个字节   # null seg
    SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)           # code seg for bootloader and kernel
    SEG_ASM(STA_W, 0x0, 0xffffffff)                 # data seg for bootloader and kernel

gdtdesc: #0x7c54 + 24字节 = 0x7c6c
    .word 0x17                                      # sizeof(gdt) - 1
    .long gdt    #0x7c56，值是54 7c          # address gdt

#内存地址是以字节8位为单位， word是2字节， long是4字节

#bootasm和bootmain在磁盘引导扇区中——第一个扇区
#bios读取第一个扇区，放在内存0x7c00处，即 本汇编的start入口函数处
#gdt和gdtdesc是数据区
#gdt是段描述符表  0x7c54
#gdtdesc是要放到GDTR寄存器中的内容 0-15位是段描述符表的大小， 16-48位是段描述符表的起始地址即gdt的内存地址
#call bootmain bootmain在0x7d00， 它前面是read_seg等代码