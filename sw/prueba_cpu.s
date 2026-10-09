# prueba_cpu.s
# Autoprueba del Espino Core, ensamblada con asm/asm.py.
# Proyecto 2 - ICC3302 Arquitectura de Computadores, UANDES 2026-2
#
# Ejecuta 16 pruebas sobre el procesador real (en simulacion con
# tb/tb_soc.v, o en la placa). Cada prueba calcula algo y lo compara
# con el valor esperado; si no coincide, salta a "fallo".
#
#   Todo correcto:  display = 10 (16 en hexadecimal), LEDs = 1111
#   Alguna falla:   display = numero de la prueba que fallo, LEDs = 0101
#
# Las pruebas 15 y 16 ademas miden con el contador de ciclos cuanto
# tarda el Espino en dos bucles, y guardan el resultado en RAM
# (0x7F0 y 0x7F4) para que el testbench calcule los ciclos por
# instruccion. Ese dato se usa en el informe para acotar el error de
# medicion del juego.

.equ PERIF,    0x80000000     # base de los perifericos
.equ DISPLAY,  0x00           # offsets dentro de PERIF
.equ LEDS,     0x04
.equ BOTONES,  0x08
.equ CONTADOR, 0x0C           # contador de ciclos (Proyecto 2)
.equ DATOS,    0x700          # zona libre de la RAM para las pruebas
.equ MEDIDAS,  0x7F0          # donde quedan las mediciones

.section .text
.global _start

_start:
    li   s0, PERIF            # s0 = base de perifericos, todo el programa
    li   s1, 0                # s1 = numero de la prueba en curso

# --- 1. suma ---------------------------------------------------------
    li   s1, 1
    li   t0, 5
    addi t1, t0, 7
    li   t2, 12
    bne  t1, t2, fallo

# --- 2. resta con resultado negativo ---------------------------------
    li   s1, 2
    li   t0, 3
    li   t1, 10
    sub  t2, t0, t1           # 3 - 10 = -7
    li   t0, -7
    bne  t2, t0, fallo

# --- 3. li de 32 bits (lui + addi con parte baja negativa) ------------
    li   s1, 3
    li   t0, 75000000         # 0x047868C0: lui 0x4787 ; addi -1856
    li   t1, 74999999
    addi t1, t1, 1
    bne  t0, t1, fallo

# --- 4. operaciones logicas ------------------------------------------
    li   s1, 4
    li   t0, 0b1100
    li   t1, 0b1010
    and  t2, t0, t1
    li   a0, 0b1000
    bne  t2, a0, fallo
    or   t2, t0, t1
    li   a0, 0b1110
    bne  t2, a0, fallo
    xor  t2, t0, t1
    li   a0, 0b0110
    bne  t2, a0, fallo
    not  t2, t0               # xori t2, t0, -1
    li   a0, -13
    bne  t2, a0, fallo
    andi t2, t1, 3
    li   a0, 2
    bne  t2, a0, fallo

# --- 5. comparaciones con y sin signo --------------------------------
    li   s1, 5
    li   t0, -1
    li   t1, 1
    slt  t2, t0, t1           # -1 < 1 con signo: 1
    li   a0, 1
    bne  t2, a0, fallo
    sltu t2, t0, t1           # 0xFFFFFFFF < 1 sin signo: 0
    bnez t2, fallo

# --- 6. saltos condicionales -----------------------------------------
    li   s1, 6
    li   t0, -5
    li   t1, 3
    blt  t0, t1, p6a          # -5 < 3: salta
    j    fallo
p6a:
    bge  t1, t0, p6b          # 3 >= -5: salta
    j    fallo
p6b:
    bltu t0, t1, fallo        # sin signo -5 es enorme: no salta
    bgeu t0, t1, p6c
    j    fallo
p6c:

# --- 7. memoria: palabra completa ------------------------------------
    li   s1, 7
    li   t0, DATOS
    li   t1, 0x12345678
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t1, t2, fallo

# --- 8. bytes con y sin signo ----------------------------------------
    li   s1, 8
    li   t1, 0x80
    sb   t1, 8(t0)
    lb   t2, 8(t0)            # extiende el signo: -128
    li   a0, -128
    bne  t2, a0, fallo
    lbu  t2, 8(t0)            # sin signo: 128
    li   a0, 128
    bne  t2, a0, fallo

# --- 9. medias palabras ----------------------------------------------
    li   s1, 9
    li   t1, 0x8001
    sh   t1, 12(t0)
    lh   t2, 12(t0)           # 0xFFFF8001 = -32767
    li   a0, -32767
    bne  t2, a0, fallo
    lhu  t2, 12(t0)
    li   a0, 0x8001
    bne  t2, a0, fallo

# --- 10. tabla en memoria con la y .word -----------------------------
    li   s1, 10
    la   t0, mascaras
    lw   t1, 12(t0)           # cuarto elemento
    li   a0, 8
    bne  t1, a0, fallo

# --- 11. subrutina con call y ret ------------------------------------
    li   s1, 11
    li   a0, 21
    call doble
    li   t0, 42
    bne  a0, t0, fallo

# --- 12. salto a una direccion calculada (jalr) ----------------------
    li   s1, 12
    la   t0, p12
    jalr ra, 0(t0)
    j    fallo                # no debe ejecutarse
p12:

# --- 13. x0 siempre vale 0 -------------------------------------------
    li   s1, 13
    addi x0, x0, 5
    bnez x0, fallo

# --- 14. el Espino ejecuta los shifts como suma ----------------------
    li   s1, 14
    li   t0, 1
    slli t0, t0, 4            # en RV32E seria 16; en el Espino da 1 + 4 = 5
    li   t1, 5
    bne  t0, t1, fallo

# --- 15. contador de ciclos: bucle de 2 instrucciones ----------------
    li   s1, 15
    lw   t0, CONTADOR(s0)
    li   t1, 1000
bucle1:
    addi t1, t1, -1
    bnez t1, bucle1
    lw   t2, CONTADOR(s0)
    sub  t2, t2, t0           # ciclos transcurridos
    li   t0, MEDIDAS
    sw   t2, 0(t0)
    li   t1, 2000             # 2000 instrucciones toman al menos 2000 ciclos
    bltu t2, t1, fallo
    li   t1, 20000
    bgeu t2, t1, fallo

# --- 16. contador de ciclos: bucle que lee los botones ---------------
    li   s1, 16
    lw   t0, CONTADOR(s0)
    li   t1, 1000
bucle2:
    lw   a0, BOTONES(s0)
    addi t1, t1, -1
    bnez t1, bucle2
    lw   t2, CONTADOR(s0)
    sub  t2, t2, t0
    li   t0, MEDIDAS
    sw   t2, 4(t0)

# --- todo correcto ---------------------------------------------------
    sw   s1, DISPLAY(s0)      # display: 10 (16 pruebas, en hexadecimal)
    li   t0, 0b1111
    sw   t0, LEDS(s0)
fin:
    j    fin

fallo:
    sw   s1, DISPLAY(s0)      # display: numero de la prueba que fallo
    li   t0, 0b0101
    sw   t0, LEDS(s0)
parado:
    j    parado

doble:
    add  a0, a0, a0
    ret

mascaras:
    .word 1, 2, 4, 8
