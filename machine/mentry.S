// See LICENSE for license details.

#include "mtrap.h"
#include "bits.h"
#include "config.h"

  .data
  .align 6
trap_table:
#define BAD_TRAP_VECTOR 0
  .dc.a bad_trap              #0 poweroff instruction address misaligned
  .dc.a pmp_trap              #1          instruction access fault
  .dc.a illegal_insn_trap     #2          illegal instruction
  .dc.a bad_trap              #3 poweroff breakpoint
  .dc.a misaligned_load_trap  #4          load address misaligned
  .dc.a pmp_trap              #5          load access fault
  .dc.a misaligned_store_trap #6          store/amo address misaligned
  .dc.a pmp_trap              #7          store/amo access fault
  .dc.a bad_trap              #8 poweroff ecall from U
  .dc.a mcall_trap            #9          ecall from S
  .dc.a bad_trap              #10poweroff R
#ifdef BBL_BOOT_MACHINE     
  .dc.a mcall_trap            #11         ecall from M
#else                       
  .dc.a bad_trap              #11poweroff ecall from N
#endif /* BBL_BOOT_MACHINE */
  .dc.a bad_trap              #12poweroff instruction page fault
#define TRAP_FROM_MACHINE_MODE_VECTOR 13 
  .dc.a __trap_from_machine_mode#14   
  .dc.a bad_trap                #15 poweroff
  .dc.a bad_trap                #16 poweroff



  .option norvc  #接下来的汇编程序不可以被汇编生成16位宽的压缩指令
  .section .text.init,"ax",@progbits
  .globl reset_vector
reset_vector:
  j do_reset  #开始


#异常和中断处理
trap_vector:
  csrrw sp, mscratch, sp            #切换栈（U、S）->M
  beqz sp, .Ltrap_from_machine_mode

  STORE a0, 10*REGBYTES(sp)
  STORE a1, 11*REGBYTES(sp)

  csrr a1, mcause #参数2
  bgez a1, .Lhandle_trap_in_machine_mode # 大于0，为异常，跳转到 Lhandle_trap_in_machine_mode

  # This is an interrupt.  Discard the mcause MSB and decode the rest.
  sll a1, a1, 1

  # Is it a machine timer interrupt?
  li a0, IRQ_M_TIMER * 2
  bne a0, a1, 1f
  # Yes.  Simply clear MTIE and raise STIP. 时钟中断处理
  li a0, MIP_MTIP  
  csrc mie, a0   #清除 M-时钟中断
  li a0, MIP_STIP 
  csrs mip, a0   #设置 S-时钟中断 

# SBI functions must return a pair of values in a0 and a1, with a0 returning an error code. 
# struct sbiret {
#       long error;
#       long value;
#   };
.Lmret:
  # Go back whence we came.
  LOAD a0, 10*REGBYTES(sp)
  LOAD a1, 11*REGBYTES(sp)
  csrrw sp, mscratch, sp        #切换栈（U、S）<- M
  mret                          #从机器模式异常处理返回


1:   #软件中断处理
  # Is it an IPI?
  li a0, IRQ_M_SOFT * 2
  bne a0, a1, .Lbad_trap

  # Yes.  First, clear the MIPI bit.
  LOAD a0, MENTRY_IPI_OFFSET(sp) 
  sw x0, (a0)
  fence

  # Now, decode the cause(s).  编译器内置宏定义
#ifdef __riscv_atomic    
  addi a0, sp, MENTRY_IPI_PENDING_OFFSET
  amoswap.w a0, x0, (a0)
#else
  lw a0, MENTRY_IPI_PENDING_OFFSET(sp)
  sw x0, MENTRY_IPI_PENDING_OFFSET(sp)
#endif
#4种ipi类型的处理方式 ，a0表示具体哪种类型
  and a1, a0, IPI_SOFT
  beqz a1, 1f
  csrs mip, MIP_SSIP  #设置  M-软件中断;  IPI_SOFT类型的实现方式 是通过软件中断
                      #                 下面的另外三种类型，是执行指令（fence.i、sfence.vma、wfi）
1:
  andi a1, a0, IPI_FENCE_I
  beqz a1, 1f
  fence.i
1:
  andi a1, a0, IPI_SFENCE_VMA
  beqz a1, 1f
  sfence.vma
1:
  andi a1, a0, IPI_HALT  # 本hart 停下来，等到a0被更改；  想要更改a0，退出halt，应该走 wfi的异常处理程序
  beqz a1, 1f
  wfi
  j 1b
1:
  j .Lmret



.Lhandle_trap_in_machine_mode:
  # Preserve the registers.  Compute the address of the trap handler.
  STORE ra, 1*REGBYTES(sp)
  STORE gp, 3*REGBYTES(sp)
  STORE tp, 4*REGBYTES(sp)
  STORE t0, 5*REGBYTES(sp)
1:auipc t0, %pcrel_hi(trap_table)  # t0 <- %hi(trap_table)
  STORE t1, 6*REGBYTES(sp)
  sll t1, a1, LOG_REGBYTES         # t1 <- mcause * ptr size
  STORE t2, 7*REGBYTES(sp)
  add t1, t0, t1                   # t1 <- %hi(trap_table)[mcause]
  STORE s0, 8*REGBYTES(sp)
  LOAD t1, %pcrel_lo(1b)(t1)       # t1 <- trap_table[mcause] 跳转地址
  STORE s1, 9*REGBYTES(sp)
  mv a0, sp                        # a0 <- regs  参数1
  STORE a2,12*REGBYTES(sp)
  csrr a2, mepc                    # a2 <- mepc  参数3
  STORE a3,13*REGBYTES(sp)
  csrrw t0, mscratch, x0           # t0 <- user sp <- 0
  STORE a4,14*REGBYTES(sp)
  STORE a5,15*REGBYTES(sp)
  STORE a6,16*REGBYTES(sp)
  STORE a7,17*REGBYTES(sp)
  STORE s2,18*REGBYTES(sp)
  STORE s3,19*REGBYTES(sp)
  STORE s4,20*REGBYTES(sp)
  STORE s5,21*REGBYTES(sp)
  STORE s6,22*REGBYTES(sp)
  STORE s7,23*REGBYTES(sp)
  STORE s8,24*REGBYTES(sp)
  STORE s9,25*REGBYTES(sp)
  STORE s10,26*REGBYTES(sp)
  STORE s11,27*REGBYTES(sp)
  STORE t3,28*REGBYTES(sp)
  STORE t4,29*REGBYTES(sp)
  STORE t5,30*REGBYTES(sp)
  STORE t6,31*REGBYTES(sp)
  STORE t0, 2*REGBYTES(sp)         # sp

#ifndef __riscv_flen
  lw tp, (sp) # Move the emulated FCSR from x0's save slot into tp.
#endif
  STORE x0, (sp) # Zero x0's save slot.

  # Invoke the handler. 跳转到对应的异常处理程序
  jalr t1

#ifndef __riscv_flen
  sw tp, (sp) # Move the emulated FCSR from tp into x0's save slot.
#endif

restore_mscratch:
  # Restore mscratch, so future traps will know they didn't come from M-mode.
  csrw mscratch, sp

restore_regs:
  # Restore all of the registers.
  LOAD ra, 1*REGBYTES(sp)
  LOAD gp, 3*REGBYTES(sp)
  LOAD tp, 4*REGBYTES(sp)
  LOAD t0, 5*REGBYTES(sp)
  LOAD t1, 6*REGBYTES(sp)
  LOAD t2, 7*REGBYTES(sp)
  LOAD s0, 8*REGBYTES(sp)
  LOAD s1, 9*REGBYTES(sp)
  LOAD a0,10*REGBYTES(sp)
  LOAD a1,11*REGBYTES(sp)
  LOAD a2,12*REGBYTES(sp)
  LOAD a3,13*REGBYTES(sp)
  LOAD a4,14*REGBYTES(sp)
  LOAD a5,15*REGBYTES(sp)
  LOAD a6,16*REGBYTES(sp)
  LOAD a7,17*REGBYTES(sp)
  LOAD s2,18*REGBYTES(sp)
  LOAD s3,19*REGBYTES(sp)
  LOAD s4,20*REGBYTES(sp)
  LOAD s5,21*REGBYTES(sp)
  LOAD s6,22*REGBYTES(sp)
  LOAD s7,23*REGBYTES(sp)
  LOAD s8,24*REGBYTES(sp)
  LOAD s9,25*REGBYTES(sp)
  LOAD s10,26*REGBYTES(sp)
  LOAD s11,27*REGBYTES(sp)
  LOAD t3,28*REGBYTES(sp)
  LOAD t4,29*REGBYTES(sp)
  LOAD t5,30*REGBYTES(sp)
  LOAD t6,31*REGBYTES(sp)
  LOAD sp, 2*REGBYTES(sp)
  mret

.Ltrap_from_machine_mode:
  csrr sp, mscratch       #（U、S）
  addi sp, sp, -INTEGER_CONTEXT_SIZE
  STORE a0,10*REGBYTES(sp) 
  STORE a1,11*REGBYTES(sp) 
  li a1, TRAP_FROM_MACHINE_MODE_VECTOR#参数2 
  j .Lhandle_trap_in_machine_mode

.Lbad_trap:
  li a1, BAD_TRAP_VECTOR
  j .Lhandle_trap_in_machine_mode

  .globl __redirect_trap
__redirect_trap:
  # reset sp to top of M-mode stack
  li t0, MACHINE_STACK_SIZE
  add sp, sp, t0
  neg t0, t0
  and sp, sp, t0
  addi sp, sp, -MENTRY_FRAME_SIZE
  j restore_mscratch

__trap_from_machine_mode:
  jal trap_from_machine_mode
  j restore_regs

do_reset:
  li x1, 0
  li x2, 0
  li x3, 0
  li x4, 0
  li x5, 0
  li x6, 0
  li x7, 0
  li x8, 0
  li x9, 0
// save a0 and a1; arguments from previous boot loader stage:
//  li x10, 0
//  li x11, 0
  li x12, 0
  li x13, 0
  li x14, 0
  li x15, 0
  li x16, 0
  li x17, 0
  li x18, 0
  li x19, 0
  li x20, 0
  li x21, 0
  li x22, 0
  li x23, 0
  li x24, 0
  li x25, 0
  li x26, 0
  li x27, 0
  li x28, 0
  li x29, 0
  li x30, 0
  li x31, 0
  csrw mscratch, x0 #清零

  # write mtvec and make sure it sticks
  la t0, trap_vector
  csrw mtvec, t0
  csrr t1, mtvec  #异常入口地址   这里写入的是M模式的中断异常入口
1:bne t0, t1, 1b  #中断向量表没设置好，死循环


  la sp, stacks + RISCV_PGSIZE - MENTRY_FRAME_SIZE  #本hart的页中申请了 MENTRY_FRAME_SIZE 大小的区域

  csrr a3, mhartid
  slli a2, a3, RISCV_PGSHIFT
  add sp, sp, a2  //选择属于 hart自己的 那一页

  bnez a3, .LmultiHartInit #如果不为0，表示有多个hart

#ifdef ZERO_BSS
  # Zero out BSS; linker script provides alignment and padding
  la t0, _fbss
  la t1, _end
  beq t0, t1, 2f
1:STORE zero, 0(t0)
  addi t0, t0, REGBYTES
  bne t0, t1, 1b
2:
#endif

  # Boot on the first hart
  j init_first_hart

.LmultiHartInit:
  # set MSIE bit to receive IPI 核间中断(Inter-Processor Interrupts,IPI）
  li a2, MIP_MSIP 
  csrw mie, a2     #使能 M-软件中断 (中断局部开关)

.LmultiHart:
#if MAX_HARTS > 1    # MAX_HARTS=8
  # wait for an IPI to signal that it's safe to boot
  wfi
  #当处理器执行到WFI指令之后，将会停止执行当前的指令流，进入一种空闲状态。
  #这种空闲状态可以被称为“休眠"状态,直到处理器接收到中断（中断局部开关必须被打开，由mie寄存器控制），处理器便被唤醒。
  #处理器被唤醒后，
  #如果中断被全局打开(mstatus寄存器的MIE域控制），则进入中断异常服务程序开始执行；
  #如果中断被全局关闭，则继续顺序执行之前停止的指令流;


  # masked harts never start
  la a4, disabled_hart_mask  # disabled_hart_mask 是由 0 号核  根据设备数设置的
  LOAD a4, 0(a4)
  srl a4, a4, a3
  andi a4, a4, 1
  bnez a4, .LmultiHart

  # only start if mip is set  等待软中断
  csrr a2, mip
  andi a2, a2, MIP_MSIP
  beqz a2, .LmultiHart

  # make sure our hart id is within a valid range
  fence
  li a2, MAX_HARTS
  bltu a3, a2, init_other_hart #另一个hart初始化
#endif
  wfi
  j .LmultiHart






  .bss
  .align RISCV_PGSHIFT
stacks:
  .skip RISCV_PGSIZE * MAX_HARTS
  # 用于分配一块连续的存储区域并初始化为指定的值，如果后面的填充值省略不写则在后面填充为0;
  # 分配了 8 个页大小的区域，给支持的最多8个hart使用
  /*

          ......
 --------------------------------5*RISCV_PGSIZE
 --------------------------------4*RISCV_PGSIZE
 --------------------------------3*RISCV_PGSIZE 
      |
  MENTRY_FRAME_SIZE
      |
 -------------------  sp2
 
 --------------------------------2*RISCV_PGSIZE
      |
  MENTRY_FRAME_SIZE
      |
 -------------------  sp1
 
 --------------------------------1*RISCV_PGSIZE
      |
  MENTRY_FRAME_SIZE
      |
 -------------------  sp0
 
 --------------------------------0
  */
