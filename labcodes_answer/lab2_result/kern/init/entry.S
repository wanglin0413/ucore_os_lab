#include <mmu.h>
#include <memlayout.h>

#KERNBASE为0xC0000000
#define REALLOC(x) (x - KERNBASE)

.text
.globl kern_entry
kern_entry:
    # load pa of boot pgdir
    #realloc相当于将其中的虚拟地址-0xC0000000
    #因此realloc之后的地址，就是页目录的起始物理地址
    movl $REALLOC(__boot_pgdir), %eax
    #放到cr3里，初始化了一个临时页目录1024个页目录
    #其中第一个对应的页表初始化为__boot_pt1，有1024个页，总共4M大小
    movl %eax, %cr3

    # enable paging
    #使能页机制
    movl %cr0, %eax
    orl $(CR0_PE | CR0_PG | CR0_AM | CR0_WP | CR0_NE | CR0_TS | CR0_EM | CR0_MP), %eax
    andl $~(CR0_TS | CR0_EM), %eax
    movl %eax, %cr0

    # update eip
    # now, eip = 0x1.....
    #在这之前，eip还是0x10000的，使能了页机制之后，应该变为0xC*的值
    #eip总是虚拟地址的值
    #将虚拟地址next的值给eax
    leal next, %eax
    # set eip = KERNBASE + 0x1.....
    #通过这一步来修改eip
    jmp *%eax
next:
     #为什么要临时映射va的0~4到pa的0~4呢，
     #至少看这里的代码，在使能页机制后，并没有涉及内存的访问，只访问了寄存器
     #todo 检查这时的各个寄存器，包括esp等，是否有对0~4Mva空间的访问
    # unmap va 0 ~ 4M, it's temporary mapping
    xorl %eax, %eax
    movl %eax, __boot_pgdir

    # set ebp, esp
    movl $0x0, %ebp
    # the kernel stack region is from bootstack -- bootstacktop,
    # the kernel stack size is KSTACKSIZE (8KB)defined in memlayout.h
    movl $bootstacktop, %esp
    # now kernel stack is ready , call the first C function
    call kern_init

# should never get here
spin:
    jmp spin

#初始化一段内核堆栈，用于内核本身的执行，以及ts中的临时内核栈，都是这个
.data
.align PGSIZE
    .globl bootstack
bootstack:
    .space KSTACKSIZE
    .globl bootstacktop
bootstacktop:

# kernel builtin pgdir
# an initial page directory (Page Directory Table, PDT)
# These page directory table and page table can be reused!
.section .data.pgdir
.align PGSIZE
#临时的页目录
#0xC0118000
__boot_pgdir:
.globl __boot_pgdir
    # map va 0 ~ 4M to pa 0 ~ 4M (temporary)
    #第一个记录表示0~4M的虚拟地址空间，其值为临时页表的物理地址
    .long REALLOC(__boot_pt1) + (PTE_P | PTE_U | PTE_W)
    #4M到3G的空间，其对应的页目录项初始化为0
    # KERNBASE >> PGSHIFT >> 10 表示一共需要这么多页目录项，<< 2表示一个页目录项4个字节，一共这么多字节
    #.-__boot_pgdir表示当前地址减去__boot_pgdir的地址，即.long的大小，表示第一个目录项已经写好了，只写剩下的目录项
    .space (KERNBASE >> PGSHIFT >> 10 << 2) - (. - __boot_pgdir) # pad to PDE of KERNBASE

    # map va KERNBASE + (0 ~ 4M) to pa 0 ~ 4M
    #表示将虚拟地址空间的3G开始的4M，所对应的页表也设置为__boot_pt1，即物理地址0-4M
    .long REALLOC(__boot_pt1) + (PTE_P | PTE_U | PTE_W)
    .space PGSIZE - (. - __boot_pgdir) # pad to PGSIZE

.set i, 0
#临时的页表
#d0xC0119000，比页目录大4096k，实际物理地址为0x119000
#这个页表将0~4M物理地址映射到一段4M（必然是连续的）的虚拟空间中，具体哪段，要看哪个页目录项指向该页表
#实际上，页表项中的值（即连续的虚拟地址 --对应的不连续的物理地址）通常不是连续的
__boot_pt1:
.rept 1024
    .long i * PGSIZE + (PTE_P | PTE_W)
    .set i, i + 1
.endr
