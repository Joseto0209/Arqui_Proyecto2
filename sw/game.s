# game.s
# Juego de reflejos para el Espino Core (Pochoco SoC, Go Board).
# Proyecto 2 - ICC3302 Arquitectura de Computadores, UANDES 2026-2
#
# Se ensambla con el ensamblador del grupo:
#   python asm/asm.py sw/game.s -o sw/game.hex
#
# ---------------------------------------------------------------------
#  Como se juega
# ---------------------------------------------------------------------
#  0. Al encender: display 00 y LEDs apagados. Cualquier boton empieza.
#  1. Cada ronda parte con los 4 LEDs encendidos durante 3 segundos.
#  2. Se enciende un solo LED, elegido de forma pseudoaleatoria, y en
#     ese instante empieza la medicion.
#  3. El jugador aprieta el boton de ese LED (boton i <-> LED i).
#     Acierto: el display muestra el tiempo en decimas de segundo
#              (23 = 2,3 s) y se suma una ronda correcta.
#     Error:   el display muestra EE, los LEDs se apagan 1 segundo y
#              se repite la ronda. Las rondas correctas se conservan.
#  4. Tras la decima ronda correcta: se muestra su tiempo 2 segundos y
#     luego el promedio de las diez, con los LEDs alternando 1001/0110.
#     Cualquier boton empieza una partida nueva.
#
# ---------------------------------------------------------------------
#  Uso de registros
# ---------------------------------------------------------------------
#   s0  base de los perifericos (0x8000_0000), fija todo el programa
#   s1  rondas correctas de la partida
#   gp  estado del generador pseudoaleatorio (LFSR de 32 bits)
#   tp  suma de los tiempos de las rondas correctas, en decimas
#   sp  puntero de pila (crece hacia abajo desde el final de la RAM)
#   a0  argumento y resultado de las subrutinas
#   a1..a5, t0..t2  temporales
#
# El Espino no ejecuta shifts (los trata como add) y RV32E no tiene
# multiplicacion ni division. Por eso las divisiones se hacen con
# restas sucesivas y "multiplicar por 16" se hace sumando 4 veces.

# =====================================================================
#  Constantes del juego (las que se pueden cambiar)
# =====================================================================
.equ FRECUENCIA,       25000000          # Hz, reloj de la Go Board
.equ CICLOS_DECIMA,    FRECUENCIA / 10   # 2.500.000 ciclos = 0,1 s
.equ DECIMAS_INICIO,   30                # fase con los 4 LEDs: 3,0 s
.equ DECIMAS_ERROR,    10                # EE con los LEDs apagados: 1,0 s
.equ DECIMAS_FINAL,    20                # tiempo de la ronda 10 antes del promedio: 2,0 s
.equ DECIMAS_PARPADEO, 5                 # parpadeo de la pantalla final: 0,5 s
.equ DECIMAS_TOPE,     99                # maximo que cabe en el display: 9,9 s
.equ RONDAS,           10                # rondas correctas por partida

# Derivadas de las anteriores (no hace falta tocarlas)
.equ CICLOS_INICIO,    DECIMAS_INICIO   * CICLOS_DECIMA     # 75.000.000
.equ CICLOS_ERROR,     DECIMAS_ERROR    * CICLOS_DECIMA
.equ CICLOS_FINAL,     DECIMAS_FINAL    * CICLOS_DECIMA
.equ CICLOS_PARPADEO,  DECIMAS_PARPADEO * CICLOS_DECIMA
.equ CICLOS_TOPE,      DECIMAS_TOPE     * CICLOS_DECIMA     # 247.500.000
.equ CICLOS_REBOTE,    CICLOS_DECIMA / 5                    # 20 ms

# =====================================================================
#  Mapa de memoria del Pochoco
# =====================================================================
.equ PERIF,    0x80000000     # base de los perifericos
.equ DISPLAY,  0x00           # escritura: byte que muestran los displays
.equ LEDS,     0x04           # escritura: bit i = LED i
.equ BOTONES,  0x08           # lectura:   bit i = boton i
.equ CONTADOR, 0x0C           # lectura:   contador de ciclos (Proyecto 2)
.equ FIN_RAM,  0x800          # 512 palabras = 2048 bytes

.equ POLINOMIO, 0x00400007    # LFSR: x^32 + x^22 + x^2 + x + 1
.equ ERROR_EE,  0xEE          # lo que muestra el display al fallar

.section .text
.global _start

# =====================================================================
#  Programa principal
# =====================================================================
_start:
    li   sp, FIN_RAM          # la pila parte en el final de la RAM
    li   s0, PERIF
    li   gp, 1                # el LFSR nunca puede valer 0
    sw   zero, LEDS(s0)
    sw   zero, DISPLAY(s0)    # pantalla de inicio: 00

# --- Espera el primer boton --------------------------------------------
# La semilla sale del contador en el momento en que una persona aprieta
# el boton, asi que la primera ronda tampoco se repite entre partidas.
esperar_inicio:
    lw   t0, BOTONES(s0)
    beqz t0, esperar_inicio
    call mezclar_semilla
    call soltar_botones

nueva_partida:
    li   s1, 0                # rondas correctas
    li   tp, 0                # suma de decimas
    sw   zero, DISPLAY(s0)

# --- Una ronda -----------------------------------------------------------
ronda:
    # 1. Los cuatro LEDs encendidos durante 3 segundos
    li   t0, 0b1111
    sw   t0, LEDS(s0)
    li   a0, CICLOS_INICIO
    call esperar

    # 2. Si el jugador mantiene un boton apretado, se espera a que lo
    #    suelte: si no, la ronda terminaria apenas se encienda el LED.
    call soltar_botones

    # 3. Elegir el LED objetivo: a0 = mascara 0001, 0010, 0100 o 1000
    call elegir_objetivo
    mv   a1, a0               # a1 = LED objetivo durante la ronda

    # 4. Encender solo ese LED y empezar a medir en la instruccion
    #    siguiente: entre ambos eventos pasa 1 ciclo (40 ns), medido en
    #    simulacion.
    sw   a1, LEDS(s0)
    lw   a2, CONTADOR(s0)     # a2 = inicio de la medicion
    li   a3, CICLOS_TOPE

    # 5. Esperar una pulsacion. En cada vuelta se calcula el tiempo
    #    transcurrido; si llega al tope, el inicio se corre para que el
    #    tiempo quede fijo en 9,9 s (asi el contador nunca da la vuelta).
esperar_boton:
    lw   t1, CONTADOR(s0)
    sub  t2, t1, a2           # t2 = ciclos desde que se encendio el LED
    bltu t2, a3, leer_botones
    sub  a2, t1, a3           # tope alcanzado: el tiempo queda en CICLOS_TOPE
leer_botones:
    lw   t0, BOTONES(s0)
    beqz t0, esperar_boton

    mv   a4, t0               # a4 = botones apretados
    mv   a5, t2               # a5 = ciclos de reaccion
    call mezclar_semilla      # el instante de la pulsacion alimenta el LFSR
    bne  a4, a1, ronda_error  # otro boton, o mas de uno: error

    # 6. Acierto: convertir a decimas, sumar y mostrar
    mv   a0, a5
    call ciclos_a_decimas     # a0 = decimas (0..99)
    add  tp, tp, a0
    call mostrar_decimas
    addi s1, s1, 1
    call soltar_botones
    li   t0, RONDAS
    blt  s1, t0, ronda
    j    fin_partida

ronda_error:
    li   t0, ERROR_EE
    sw   t0, DISPLAY(s0)      # EE
    sw   zero, LEDS(s0)       # LEDs apagados
    call soltar_botones
    li   a0, CICLOS_ERROR
    call esperar
    j    ronda                # misma ronda; s1 y tp no cambian

# --- Fin de la partida ---------------------------------------------------
fin_partida:
    sw   zero, LEDS(s0)
    li   a0, CICLOS_FINAL     # el tiempo de la ronda 10 queda visible
    call esperar
    mv   a0, tp
    call promedio             # a0 = round(suma / RONDAS)
    call mostrar_decimas
    li   a4, 0b1001
parpadeo_final:
    sw   a4, LEDS(s0)
    xori a4, a4, 0b1111       # 1001 <-> 0110
    li   a0, CICLOS_PARPADEO
    call esperar_o_boton
    beqz a0, parpadeo_final
    call mezclar_semilla
    call soltar_botones
    j    nueva_partida

# =====================================================================
#  Subrutinas
# =====================================================================

# --- esperar: a0 = ciclos ------------------------------------------------
# Espera activa usando el contador. Compara diferencias (ahora - inicio),
# por lo que funciona aunque el contador de la vuelta entre medio.
esperar:
    lw   t0, CONTADOR(s0)     # inicio
esp_1:
    lw   t1, CONTADOR(s0)
    sub  t1, t1, t0
    bltu t1, a0, esp_1
    ret

# --- esperar_o_boton: a0 = ciclos -> a0 = botones (0 si se acabo el tiempo)
esperar_o_boton:
    lw   t0, CONTADOR(s0)
eob_1:
    lw   t1, BOTONES(s0)
    bnez t1, eob_2
    lw   t1, CONTADOR(s0)
    sub  t1, t1, t0
    bltu t1, a0, eob_1
    li   a0, 0
    ret
eob_2:
    mv   a0, t1
    ret

# --- soltar_botones --------------------------------------------------------
# Antirrebote por software: espera que no haya botones apretados y que se
# mantengan sueltos 20 ms. Llama a otra subrutina, asi que guarda ra en
# la pila.
soltar_botones:
    addi sp, sp, -4
    sw   ra, 0(sp)
sol_1:
    lw   t0, BOTONES(s0)
    bnez t0, sol_1
    li   a0, CICLOS_REBOTE
    call esperar
    lw   t0, BOTONES(s0)
    bnez t0, sol_1            # rebote: volver a esperar
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

# --- mezclar_semilla ---------------------------------------------------------
# gp = gp XOR contador. El contador en el instante de una pulsacion humana
# es impredecible, lo que agrega azar real al generador.
mezclar_semilla:
    lw   t0, CONTADOR(s0)
    xor  gp, gp, t0
    bnez gp, mez_1
    li   gp, 1                # 0 dejaria al LFSR fijo en 0
mez_1:
    ret

# --- elegir_objetivo -> a0 = mascara del LED (1, 2, 4 u 8) -------------------
# Avanza 8 pasos un LFSR de Galois de 32 bits (desplazar a la izquierda y,
# si salio un 1 por el bit 31, hacer XOR con el polinomio). Desplazar es
# sumar el registro consigo mismo, porque el Espino no tiene shifts.
# El indice se arma con los bits 16 y 17 del estado, que se leen con una
# mascara y snez (sin shifts).
elegir_objetivo:
    li   t2, 8                # pasos del LFSR
    li   t1, POLINOMIO
eo_1:
    bgez gp, eo_2             # bit 31 = 0
    add  gp, gp, gp           # bit 31 = 1: desplazar y aplicar el polinomio
    xor  gp, gp, t1
    j    eo_3
eo_2:
    add  gp, gp, gp
eo_3:
    addi t2, t2, -1
    bnez t2, eo_1

    li   t1, 0x10000          # bit 16
    and  t0, gp, t1
    snez t0, t0               # t0 = bit 16
    add  t1, t1, t1           # bit 17
    and  t2, gp, t1
    snez t2, t2               # t2 = bit 17
    add  t2, t2, t2
    add  t0, t0, t2           # t0 = indice 0..3 = 2*bit17 + bit16

    add  t0, t0, t0           # indice * 4 = posicion en la tabla
    add  t0, t0, t0
    la   t1, mascaras
    add  t1, t1, t0
    lw   a0, 0(t1)
    ret

# --- ciclos_a_decimas: a0 = ciclos -> a0 = decimas (0..99) -----------------
# Division entera por CICLOS_DECIMA con restas sucesivas. Trunca, como un
# cronometro: 2,38 s se muestra como 23.
ciclos_a_decimas:
    li   t0, 0                # cociente
    li   t1, CICLOS_DECIMA
cad_1:
    bltu a0, t1, cad_2
    sub  a0, a0, t1
    addi t0, t0, 1
    j    cad_1
cad_2:
    li   t1, DECIMAS_TOPE
    bleu t0, t1, cad_3
    mv   t0, t1
cad_3:
    mv   a0, t0
    ret

# --- promedio: a0 = suma de decimas -> a0 = suma / RONDAS, redondeado -------
# Redondea al mas cercano: si el resto es al menos la mitad de RONDAS
# (2 * resto >= RONDAS), sube una decima.
promedio:
    li   t0, 0
    li   t1, RONDAS
pro_1:
    bltu a0, t1, pro_2
    sub  a0, a0, t1
    addi t0, t0, 1
    j    pro_1
pro_2:
    add  a0, a0, a0           # 2 * resto
    bltu a0, t1, pro_3
    addi t0, t0, 1
pro_3:
    mv   a0, t0
    ret

# --- mostrar_decimas: a0 = 0..99 -------------------------------------------
# Separa decenas y unidades (restando 10) y escribe 16*decenas + unidades:
# cada digito queda en su propio display. 23 -> 0x23 -> "2" "3".
mostrar_decimas:
    li   t0, 0                # decenas
    li   t1, 10
md_1:
    bltu a0, t1, md_2
    sub  a0, a0, t1
    addi t0, t0, 1
    j    md_1
md_2:
    add  t0, t0, t0           # x2
    add  t0, t0, t0           # x4
    add  t0, t0, t0           # x8
    add  t0, t0, t0           # x16: equivale a desplazar 4 bits
    or   t0, t0, a0
    sw   t0, DISPLAY(s0)
    ret

# =====================================================================
#  Datos
# =====================================================================
mascaras:
    .word 0b0001, 0b0010, 0b0100, 0b1000
