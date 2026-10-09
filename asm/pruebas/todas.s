# todas.s - usa todas las instrucciones y pseudo-instrucciones que acepta
# asm.py, con inmediatos en sus limites. La salida se compara palabra por
# palabra contra la del ensamblador GNU de RISC-V (archivo todas.hex).

.section .text
.global _start

.equ BASE, 0x80000000
.equ TRES_SEG, 3 * 25000000
.equ NEG, -(4 + 4)

_start:
# --- Formato R ---
    add  x5, x6, x7
    sub  a0, a1, a2
    sll  t0, t1, t2
    slt  s0, s1, a5
    sltu x15, x14, x13
    xor  ra, sp, gp
    srl  tp, x8, x9
    sra  x10, x11, x12
    or   zero, x1, x15
    and  fp, a3, a4

# --- Formato I aritmetico, con los limites -2048 y 2047 ---
    addi x1, x2, -2048
    addi x1, x2, 2047
    slti x3, x4, -1
    sltiu x5, x6, 100
    xori x7, x8, 0x7FF
    ori  x9, x10, -0x800
    andi x11, x12, 0b1010
    slli x1, x2, 31
    srli x3, x4, 1
    srai x5, x6, 16

# --- Cargas y almacenamientos ---
    lb   x1, -1(x2)
    lh   x3, 2(x4)
    lw   x5, 2047(x6)
    lbu  x7, -2048(x8)
    lhu  x9, 0(x10)
    lw   x11, (x12)
    sb   x13, -1(x14)
    sh   x15, 6(x1)
    sw   x2, 12(x3)
    sw   x4, -2048(x5)

# --- Saltos condicionales hacia atras y adelante ---
atras:
    beq  x1, x2, atras
    bne  x3, x4, adelante
    blt  x5, x6, atras
    bge  x7, x8, adelante
    bltu x9, x10, atras
    bgeu x11, x12, adelante
adelante:

# --- U y J ---
    lui   x1, 0xFFFFF
    lui   x2, 0
    auipc x3, 0x12345
    jal   x1, _start
    jal   fin
    jalr  x1, 4(x2)
    jalr  x3, x4, -8
    jalr  x5

# --- Sistema ---
    fence
    ecall
    ebreak

# --- Pseudo-instrucciones ---
    nop
    mv   x5, x6
    not  x7, x8
    neg  x9, x10
    seqz x11, x12
    snez x13, x14
    li   x1, 0
    li   x1, 2047
    li   x1, -2048
    li   x1, 2048
    li   x1, -1
    li   x2, 0x80000000
    li   x3, 0x80000004
    li   x4, 0x12345FFF
    li   x5, 75000000
    li   x6, TRES_SEG
    li   x7, BASE + 12
    li   x8, NEG
    li   x9, 0xFFFFFFFF
    li   x10, 2500000
    la   x11, datos
    beqz x1, atras
    bnez x2, fin
    bltz x3, atras
    bgez x4, fin
    blez x5, atras
    bgtz x6, fin
    bgt  x7, x8, atras
    ble  x9, x10, fin
    bgtu x11, x12, atras
    bleu x13, x14, fin
    j    atras
    call fin
    jr   x5
    ret

fin:
    j fin

datos:
    .word 0x12345678, -1, 1
    .word BASE + 4
