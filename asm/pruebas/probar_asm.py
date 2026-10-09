#!/usr/bin/env python3
# probar_asm.py
# Pruebas del ensamblador, con el mismo formato PASS/FAIL de los testbenches.
#
# Correr desde la raiz del repositorio:
#   python asm/pruebas/probar_asm.py
#
# Grupos de pruebas:
#   1. Programas completos comparados palabra por palabra contra una
#      referencia generada con el ensamblador GNU de RISC-V:
#        - los tres ejemplos del Pochoco (sw/*.hex oficiales)
#        - todas.s, que usa todas las instrucciones y pseudo-instrucciones
#          (asm/pruebas/todas.hex se genero una vez con riscv-none-elf-as;
#          el ensamblador del grupo no lo usa en ningun momento)
#   2. Codificaciones conocidas, sacadas de las diapositivas del curso.
#   3. Pseudo-instruccion li, etiquetas adelantadas, .equ y -D.
#   4. Validacion: cada error debe detectarse con su numero de linea.

import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.normpath(os.path.join(AQUI, "..", ".."))
sys.path.insert(0, os.path.join(RAIZ, "asm"))

from asm import Ensamblador   # noqa: E402

pasadas = 0
total = 0


def revisar(condicion, etiqueta):
    global pasadas, total
    total += 1
    if condicion:
        pasadas += 1
        print(f"PASS {etiqueta}")
    else:
        print(f"FAIL {etiqueta}")


def ensamblar(texto, definiciones=None, palabras_ram=512):
    ens = Ensamblador(definiciones, palabras_ram)
    salida = ens.ensamblar(texto)
    palabras = None if salida is None else [p for _, p, _, _ in salida]
    return palabras, ens


def leer(ruta):
    with open(os.path.join(RAIZ, ruta), encoding="utf-8") as f:
        return f.read()


def leer_hex(ruta):
    return [int(l, 16) for l in leer(ruta).split()]


def falla_con(texto, mensaje, linea, **kw):
    """El programa debe fallar con 'mensaje' en la linea indicada."""
    palabras, ens = ensamblar(texto, **kw)
    errores = "\n".join(ens.errores)
    return palabras is None and mensaje in errores and f"linea {linea}:" in errores


# ---------------------------------------------------------------------
print("--- 1. Programas completos contra la referencia GNU ---")
for nombre in ("blink", "7seg", "buttons_leds"):
    palabras, _ = ensamblar(leer(f"sw/{nombre}.s"))
    revisar(palabras == leer_hex(f"sw/{nombre}.hex"),
            f"sw/{nombre}.s igual a sw/{nombre}.hex oficial")

palabras, ens = ensamblar(leer("asm/pruebas/todas.s"))
referencia = leer_hex("asm/pruebas/todas.hex")
revisar(palabras == referencia,
        f"todas.s igual a GNU ({len(referencia)} palabras, todas las instrucciones)")

# ---------------------------------------------------------------------
print("--- 2. Codificaciones de las diapositivas ---")
casos = [
    ("add x5, x6, x7",   0x007302B3),   # 0000000 00111 00110 000 00101 0110011
    ("add x9, x12, x13", 0x00D604B3),   # 0000000 01101 01100 000 01001 0110011
    ("lui x6, 0x80000",  0x80000337),
    ("addi x5, x0, 0x55", 0x05500293),
    ("sw x5, 4(x6)",     0x00532223),
    ("lw x5, 8(x6)",     0x00832283),
]
for fuente, esperado in casos:
    palabras, _ = ensamblar(fuente)
    revisar(palabras == [esperado], f"{fuente:<18} = {esperado:08x}")

# ---------------------------------------------------------------------
print("--- 3. li, etiquetas, .equ y -D ---")
palabras, _ = ensamblar("li x5, 75000000")
revisar(palabras == [0x047872B7, 0x8C028293],
        "li 75.000.000 = lui 0x4787 + addi -1856 (parte baja negativa)")

palabras, _ = ensamblar("li x5, 2500000")
revisar(palabras == [0x002622B7, 0x5A028293], "li 2.500.000 = lui 0x262 + addi 1440")

palabras, _ = ensamblar("li x6, 0x80000000")
revisar(palabras == [0x80000337], "li 0x80000000 cabe en un solo lui")

palabras, _ = ensamblar("li x7, -1")
revisar(palabras == [0xFFF00393], "li -1 cabe en un solo addi")

palabras, _ = ensamblar("    beq x0, x0, fin\n    nop\nfin:\n    nop")
revisar(palabras is not None and palabras[0] == 0x00000463,
        "salto a una etiqueta definida mas abajo (+8)")

palabras, _ = ensamblar("li x1, dato\nnop\ndato: .word 7")
revisar(palabras is not None and len(palabras) == 4 and palabras[1] == 0x00C08093,
        "li con etiqueta reserva 2 palabras y carga su direccion (12)")

palabras, _ = ensamblar(".equ DECIMA, 25 * 100000\nli x1, DECIMA")
revisar(palabras == [0x002620B7, 0x5A008093], ".equ con expresion 25 * 100000")

palabras, _ = ensamblar(".equ DECIMA, 2500000\nli x1, DECIMA", {"DECIMA": 250})
revisar(palabras == [0x0FA00093], "-D DECIMA=250 reemplaza el .equ (addi 250)")

palabras, ens = ensamblar("slli x1, x1, 1")
revisar(palabras is not None and len(ens.advertencias) == 1,
        "un shift se codifica pero avisa que el Espino no lo ejecuta")

# ---------------------------------------------------------------------
print("--- 4. Errores detectados con su numero de linea ---")
revisar(falla_con("nop\nj nada", "simbolo no definido: 'nada'", 2),
        "etiqueta no definida")
revisar(falla_con("a:\nnop\na:", "ya estaba definida", 3),
        "etiqueta repetida")
revisar(falla_con("add x16, x1, x2", "no existe en RV32E", 1),
        "registro x16 no existe en RV32E")
revisar(falla_con("nop\nmv a6, a0", "no existe en RV32E", 2),
        "registro a6 no existe en RV32E")
revisar(falla_con("addi x1, x0, 2048", "fuera de rango", 1),
        "inmediato de 12 bits fuera de rango (2048)")
revisar(falla_con("lui x1, 0x100000", "fuera de rango", 1),
        "inmediato de lui fuera de rango (21 bits)")
revisar(falla_con("nop\nnop\nmul x1, x2, x3", "instruccion desconocida", 3),
        "instruccion que no es de RV32E (mul)")
revisar(falla_con("add x1, x2", "se esperaban 3 operandos", 1),
        "cantidad de operandos incorrecta")
revisar(falla_con("lw x1, x2", "offset(registro)", 1),
        "operando de memoria sin offset(registro)")
revisar(falla_con("beq x0, x0, lejos\n.word " + ", ".join(["0"] * 1100) + "\nlejos: nop",
                  "fuera de rango", 1, palabras_ram=4096),
        "salto condicional mas alla de 4 KiB")
palabras, ens = ensamblar(".word " + ", ".join(["0"] * 513))
revisar(palabras is None and "RAM del Pochoco tiene 512" in "\n".join(ens.errores),
        "programa mas grande que la RAM (513 palabras)")
revisar(falla_con(".equ A, B + 1", "no esta definido antes", 1),
        ".equ que usa una constante no definida")

_, ens = ensamblar("add x16, x1, x2\nnop\naddi x1, x0, 5000\nfoo x1")
revisar(len(ens.errores) == 3, "informa todos los errores de una vez (3)")

# ---------------------------------------------------------------------
print("")
print(f"Pruebas aprobadas: {pasadas}/{total}")
if pasadas == total:
    print("RESULTADO: el ensamblador funciona.")
else:
    print("RESULTADO: hay pruebas que fallaron.")
sys.exit(0 if pasadas == total else 1)
