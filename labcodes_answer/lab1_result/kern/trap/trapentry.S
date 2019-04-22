#include <memlayout.h>

# vectors.S sends all traps here.
.text
.globl __alltraps
__alltraps:
    # push registers to build a trap frame
    # therefore make the stack look like a struct trapframe
    pushl %ds
    pushl %es
    pushl %fs
    pushl %gs
    pushal

    # load GD_KDATA into %ds and %es to set up data segments for kernel
    movl $GD_KDATA, %eax
    movw %ax, %ds
    movw %ax, %es

    # push %esp to pass a pointer to the trapframe as an argument to trap()
    pushl %esp //这时esp= 7b4c，所以tf=7b4c
    //并且，这个esp位置在7b48

    # call trap(tf), where tf=%esp
    //经过几次call，每次call都要压栈参数tf，到dispatch的时候，tf变成了7b28
    call trap

    //trap方法内部，将7b48处改成了10f920，所以popl的时候，esp就变成了10f920
    # pop the pushed stack pointer
    popl %esp

    # return falls through to trapret...
.globl __trapret
__trapret:
    # restore registers from stack
    //这时弹出的时候，就弹的是switchk2u中的寄存器的值了
    popal

    # restore %ds, %es, %fs and %gs
    popl %gs
    popl %fs
    popl %es
    popl %ds

    # get rid of the trap number and error code
    //这一步是为了跳过错误码和中断向量，因为硬件返回时不管这个，由软件来处理
    addl $0x8, %esp
    //iret这一步会由硬件处理eflags，cs，ip，esp，ss
    iret

