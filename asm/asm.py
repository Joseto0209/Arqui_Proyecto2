#!/usr/bin/env python3
# asm.py
# Ensamblador RV32E para el Espino Core del Pochoco SoC.
# Proyecto 2 - ICC3302 Arquitectura de Computadores, UANDES 2026-2
#
# Lee un archivo en assembly (por ejemplo sw/game.s) y escribe el .hex
# que la RAM del Pochoco carga con $readmemh: una palabra de 32 bits en
# hexadecimal por linea, empezando en la direccion 0x0000_0000.
#
# Uso (desde la raiz del repositorio):
#
#   python asm/asm.py sw/game.s -o sw/game.hex
#   python asm/asm.py sw/game.s -o sw/game.hex -l build/game.lst
#   python asm/asm.py sw/game.s -o build/game_sim.hex -D CICLOS_DECIMA=250
#
#   -o  archivo .hex de salida
#   -l  listado: direccion, palabra, formato, campos y linea fuente
#   -D  redefine una constante .equ sin editar el archivo fuente
#
# Funciona en dos pasadas:
#
#   Pasada 1: recorre el programa asignando una direccion a cada linea.
#             Asi conoce la direccion de todas las etiquetas, incluso las
#             que aparecen despues de la instruccion que las usa.
#   Pasada 2: codifica cada instruccion en sus 32 bits, ya con todas las
#             etiquetas resueltas.
#
# No usa ninguna biblioteca externa ni invoca otro ensamblador.

import argparse
import re
import sys


# =====================================================================
#  Registros
# =====================================================================
# RV32E tiene 16 registros: x0..x15. Se aceptan tambien los nombres de
# la convencion de llamadas (ABI). Los registros x16..x31 existen en
# RV32I pero no en RV32E, y se rechazan con un mensaje explicito.

NOMBRES_ABI = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7,
    "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15,
}

NOMBRES_SOLO_RV32I = {
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9",
    "s10", "s11", "t3", "t4", "t5", "t6",
}


class ErrorEnsamblado(Exception):
    """Error en una linea del programa. Se informa con su numero de linea."""


class SimboloPendiente(Exception):
    """Etiqueta todavia desconocida durante la pasada 1."""


def registro(texto):
    """Convierte 'x5', 't0', 'zero', etc. en el numero de registro."""
    t = texto.strip().lower()
    if t in NOMBRES_ABI:
        return NOMBRES_ABI[t]
    m = re.fullmatch(r"x(\d+)", t)
    if m:
        n = int(m.group(1))
        if n <= 15:
            return n
        if n <= 31:
            raise ErrorEnsamblado(f"el registro {texto} no existe en RV32E (solo x0..x15)")
    if t in NOMBRES_SOLO_RV32I:
        raise ErrorEnsamblado(f"el registro {texto} no existe en RV32E (solo x0..x15)")
    raise ErrorEnsamblado(f"registro invalido: '{texto}'")


# =====================================================================
#  Tablas de instrucciones
# =====================================================================
# Cada instruccion queda definida por su opcode y, segun el formato, por
# funct3 y funct7. Son los mismos valores que reconoce espino_decoder.v.

OP_LOAD   = 0b0000011
OP_MISC   = 0b0001111
OP_OPIMM  = 0b0010011
OP_AUIPC  = 0b0010111
OP_STORE  = 0b0100011
OP_OP     = 0b0110011
OP_LUI    = 0b0110111
OP_BRANCH = 0b1100011
OP_JALR   = 0b1100111
OP_JAL    = 0b1101111
OP_SYSTEM = 0b1110011

# Formato R: rd, rs1, rs2           -> (funct3, funct7)
TIPO_R = {
    "add":  (0b000, 0b0000000), "sub":  (0b000, 0b0100000),
    "sll":  (0b001, 0b0000000), "slt":  (0b010, 0b0000000),
    "sltu": (0b011, 0b0000000), "xor":  (0b100, 0b0000000),
    "srl":  (0b101, 0b0000000), "sra":  (0b101, 0b0100000),
    "or":   (0b110, 0b0000000), "and":  (0b111, 0b0000000),
}

# Formato I aritmetico: rd, rs1, inmediato de 12 bits -> funct3
TIPO_I = {
    "addi": 0b000, "slti": 0b010, "sltiu": 0b011,
    "xori": 0b100, "ori":  0b110, "andi":  0b111,
}

# Desplazamientos con inmediato: rd, rs1, shamt     -> (funct3, funct7)
TIPO_SHIFT = {
    "slli": (0b001, 0b0000000),
    "srli": (0b101, 0b0000000),
    "srai": (0b101, 0b0100000),
}

# Cargas: rd, offset(rs1)                           -> funct3
CARGAS = {"lb": 0b000, "lh": 0b001, "lw": 0b010, "lbu": 0b100, "lhu": 0b101}

# Almacenamientos: rs2, offset(rs1)                 -> funct3
STORES = {"sb": 0b000, "sh": 0b001, "sw": 0b010}

# Saltos condicionales: rs1, rs2, destino           -> funct3
SALTOS = {
    "beq": 0b000, "bne": 0b001, "blt": 0b100,
    "bge": 0b101, "bltu": 0b110, "bgeu": 0b111,
}

# El Espino decodifica los shifts pero su ALU los tiene desactivados:
# se ejecutan como add. Se codifican igual, con una advertencia.
SHIFTS_DESACTIVADOS = {"sll", "srl", "sra", "slli", "srli", "srai"}

# Pseudo-instrucciones de salto contra cero: rs, etiqueta
#   nombre -> (salto real, si rs va como segundo operando)
CONTRA_CERO = {
    "beqz": ("beq", False), "bnez": ("bne", False),
    "bltz": ("blt", False), "bgez": ("bge", False),
    "blez": ("bge", True),  "bgtz": ("blt", True),
}

# Pseudo-instrucciones de salto con los operandos invertidos:
#   bgt a, b, L  =  blt b, a, L
INVERTIDOS = {"bgt": "blt", "ble": "bge", "bgtu": "bltu", "bleu": "bgeu"}

OTRAS = {"lui", "auipc", "jal", "jalr", "fence", "ecall", "ebreak",
         "nop", "li", "la", "mv", "not", "neg", "seqz", "snez",
         "j", "call", "jr", "ret"}

CONOCIDAS = (set(TIPO_R) | set(TIPO_I) | set(TIPO_SHIFT) | set(CARGAS) | set(STORES)
             | set(SALTOS) | set(CONTRA_CERO) | set(INVERTIDOS) | OTRAS)


# =====================================================================
#  Codificacion de los seis formatos de RISC-V
# =====================================================================
# Cada funcion devuelve (palabra, descripcion_de_campos). La descripcion
# va al listado (-l) y muestra los bits de cada campo.

def bits(valor, ancho):
    return format(valor & ((1 << ancho) - 1), f"0{ancho}b")


def formato_r(op, rd, f3, rs1, rs2, f7):
    palabra = (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
    campos = (f"R f7={bits(f7,7)} rs2={bits(rs2,5)} rs1={bits(rs1,5)} "
              f"f3={bits(f3,3)} rd={bits(rd,5)} op={bits(op,7)}")
    return palabra, campos


def formato_i(op, rd, f3, rs1, imm):
    palabra = ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
    campos = (f"I imm={bits(imm,12)} rs1={bits(rs1,5)} "
              f"f3={bits(f3,3)} rd={bits(rd,5)} op={bits(op,7)}")
    return palabra, campos


def formato_s(op, f3, rs1, rs2, imm):
    palabra = (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) \
              | (f3 << 12) | ((imm & 0x1F) << 7) | op
    campos = (f"S imm[11:5]={bits(imm>>5,7)} rs2={bits(rs2,5)} rs1={bits(rs1,5)} "
              f"f3={bits(f3,3)} imm[4:0]={bits(imm,5)} op={bits(op,7)}")
    return palabra, campos


def formato_b(op, f3, rs1, rs2, off):
    # El desplazamiento de 13 bits (el bit 0 siempre es 0) se reparte
    # en la palabra como imm[12|10:5] ... imm[4:1|11].
    b12  = (off >> 12) & 0x1
    b11  = (off >> 11) & 0x1
    b10_5 = (off >> 5) & 0x3F
    b4_1 = (off >> 1) & 0xF
    palabra = (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) \
              | (f3 << 12) | (b4_1 << 8) | (b11 << 7) | op
    campos = (f"B imm[12|10:5]={b12}|{bits(b10_5,6)} rs2={bits(rs2,5)} rs1={bits(rs1,5)} "
              f"f3={bits(f3,3)} imm[4:1|11]={bits(b4_1,4)}|{b11} op={bits(op,7)}")
    return palabra, campos


def formato_u(op, rd, imm20):
    palabra = ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op
    campos = f"U imm={bits(imm20,20)} rd={bits(rd,5)} op={bits(op,7)}"
    return palabra, campos


def formato_j(op, rd, off):
    # Desplazamiento de 21 bits repartido como imm[20|10:1|11|19:12].
    b20    = (off >> 20) & 0x1
    b10_1  = (off >> 1) & 0x3FF
    b11    = (off >> 11) & 0x1
    b19_12 = (off >> 12) & 0xFF
    palabra = (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | (rd << 7) | op
    campos = (f"J imm[20|10:1|11|19:12]={b20}|{bits(b10_1,10)}|{b11}|{bits(b19_12,8)} "
              f"rd={bits(rd,5)} op={bits(op,7)}")
    return palabra, campos


# =====================================================================
#  Rangos de los inmediatos
# =====================================================================

def revisar_rango(valor, minimo, maximo, que):
    if not (minimo <= valor <= maximo):
        raise ErrorEnsamblado(f"{que} fuera de rango: {valor} (permitido {minimo} a {maximo})")
    return valor


def imm12(valor):
    return revisar_rango(valor, -2048, 2047, "inmediato de 12 bits")


def partir_hi_lo(valor):
    """Divide un valor de 32 bits en la parte alta para lui (20 bits)
    y la baja para addi (12 bits con signo), tal que hi*4096 + lo = valor.

    Como addi extiende el signo de lo, cuando el bit 11 de valor es 1 la
    parte baja es negativa y hay que sumar 1 a la parte alta para
    compensar. Ejemplo: 75.000.000 = 0x047868C0
        lo = 0x8C0 - 0x1000 = -1856
        hi = (0x047868C0 + 1856) >> 12 = 0x04787
        0x04787000 - 1856 = 0x047868C0
    """
    valor &= 0xFFFFFFFF
    lo = valor & 0xFFF
    if lo >= 0x800:
        lo -= 0x1000
    hi = ((valor - lo) >> 12) & 0xFFFFF
    return hi, lo


def a_32_bits(valor):
    """Acepta valores con signo (-2^31..) o sin signo (..2^32-1)."""
    revisar_rango(valor, -(1 << 31), (1 << 32) - 1, "constante de 32 bits")
    valor &= 0xFFFFFFFF
    return valor - (1 << 32) if valor >= (1 << 31) else valor


# =====================================================================
#  Expresiones: numeros, constantes, etiquetas y + - * / ( )
# =====================================================================

TOKEN = re.compile(r"\s*(0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*|[A-Za-z_.][\w.]*|[-+*/()])")


class Evaluador:
    def __init__(self, constantes, etiquetas, pasada):
        self.constantes = constantes
        self.etiquetas = etiquetas
        self.pasada = pasada

    def evaluar(self, texto):
        texto = texto.strip()
        if not texto:
            raise ErrorEnsamblado("falta un valor")
        self.tokens = []
        pos = 0
        while pos < len(texto):
            m = TOKEN.match(texto, pos)
            if not m:
                raise ErrorEnsamblado(f"expresion invalida: '{texto}'")
            self.tokens.append(m.group(1))
            pos = m.end()
            while pos < len(texto) and texto[pos].isspace():
                pos += 1
        self.i = 0
        valor = self._suma()
        if self.i != len(self.tokens):
            raise ErrorEnsamblado(f"expresion invalida: '{texto}'")
        return valor

    def _ver(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else None

    def _tomar(self):
        t = self._ver()
        self.i += 1
        return t

    def _suma(self):
        valor = self._producto()
        while self._ver() in ("+", "-"):
            if self._tomar() == "+":
                valor += self._producto()
            else:
                valor -= self._producto()
        return valor

    def _producto(self):
        valor = self._unario()
        while self._ver() in ("*", "/"):
            op = self._tomar()
            derecha = self._unario()
            if op == "*":
                valor *= derecha
            else:
                if derecha == 0:
                    raise ErrorEnsamblado("division por cero")
                cociente = abs(valor) // abs(derecha)     # division entera exacta
                valor = cociente if (valor < 0) == (derecha < 0) else -cociente
        return valor

    def _unario(self):
        t = self._ver()
        if t == "-":
            self._tomar()
            return -self._unario()
        if t == "+":
            self._tomar()
            return self._unario()
        return self._atomo()

    def _atomo(self):
        t = self._tomar()
        if t is None:
            raise ErrorEnsamblado("expresion incompleta")
        if t == "(":
            valor = self._suma()
            if self._tomar() != ")":
                raise ErrorEnsamblado("falta ')'")
            return valor
        sin_guiones = t.replace("_", "")
        if re.fullmatch(r"0[xX][0-9a-fA-F]+", sin_guiones):
            return int(sin_guiones, 16)
        if re.fullmatch(r"0[bB][01]+", sin_guiones):
            return int(sin_guiones, 2)
        if re.fullmatch(r"\d+", sin_guiones):
            return int(sin_guiones, 10)
        if t in self.constantes:
            return self.constantes[t]
        if t in self.etiquetas:
            return self.etiquetas[t]
        if self.pasada == 1:
            raise SimboloPendiente(t)
        raise ErrorEnsamblado(f"simbolo no definido: '{t}'")


# =====================================================================
#  Lectura de una linea
# =====================================================================

ETIQUETA = re.compile(r"^\s*([A-Za-z_.][\w.]*)\s*:")
OPERANDO_MEMORIA = re.compile(r"^(.*)\(\s*([\w]+)\s*\)$")


def quitar_comentario(linea):
    return linea.split("#", 1)[0]


def separar_operandos(texto):
    texto = texto.strip()
    if not texto:
        return []
    return [o.strip() for o in texto.split(",")]


class Linea:
    """Una instruccion, pseudo-instruccion o .word, ya ubicada en memoria."""
    def __init__(self, numero, fuente, direccion, nombre, operandos, palabras):
        self.numero = numero
        self.fuente = fuente
        self.direccion = direccion
        self.nombre = nombre
        self.operandos = operandos
        self.palabras = palabras      # cuantas palabras de 32 bits ocupa


# =====================================================================
#  Ensamblador
# =====================================================================

class Ensamblador:
    def __init__(self, definiciones=None, palabras_ram=512):
        self.definiciones = dict(definiciones or {})   # -D NOMBRE=VALOR
        self.constantes = dict(self.definiciones)
        self.etiquetas = {}
        self.lineas = []
        self._errores = []
        self.advertencias = []
        self.palabras_ram = palabras_ram

    # ------------------------------------------------------------------
    def error(self, numero, fuente, mensaje):
        self._errores.append((numero, f"linea {numero}: {mensaje}\n    {fuente.strip()}"))

    @property
    def errores(self):
        """Todos los errores, ordenados por numero de linea."""
        return [texto for _, texto in sorted(self._errores, key=lambda e: e[0])]

    def advertencia(self, numero, fuente, mensaje):
        self.advertencias.append(f"linea {numero}: {mensaje}\n    {fuente.strip()}")

    def valor(self, texto, pasada):
        return Evaluador(self.constantes, self.etiquetas, pasada).evaluar(texto)

    # ------------------------------------------------------------------
    #  Pasada 1: direcciones, etiquetas y constantes
    # ------------------------------------------------------------------
    def pasada1(self, texto):
        direccion = 0
        for numero, fuente in enumerate(texto.splitlines(), start=1):
            resto = quitar_comentario(fuente)
            try:
                # Una o mas etiquetas al inicio de la linea
                while True:
                    m = ETIQUETA.match(resto)
                    if not m:
                        break
                    nombre = m.group(1)
                    if nombre in self.etiquetas:
                        raise ErrorEnsamblado(f"la etiqueta '{nombre}' ya estaba definida")
                    if nombre in self.constantes:
                        raise ErrorEnsamblado(f"'{nombre}' ya es una constante .equ")
                    self.etiquetas[nombre] = direccion
                    resto = resto[m.end():]

                resto = resto.strip()
                if not resto:
                    continue
                partes = resto.split(None, 1)
                nombre = partes[0].lower()
                operandos = separar_operandos(partes[1] if len(partes) > 1 else "")

                if nombre.startswith("."):
                    direccion = self.directiva(numero, fuente, nombre, operandos, direccion)
                    continue

                palabras = self.tamano(nombre, operandos)
                self.lineas.append(Linea(numero, fuente, direccion, nombre, operandos, palabras))
                direccion += 4 * palabras
            except ErrorEnsamblado as e:
                self.error(numero, fuente, str(e))

        if direccion > 4 * self.palabras_ram:
            self._errores.append((0,
                f"el programa ocupa {direccion // 4} palabras y la RAM del Pochoco "
                f"tiene {self.palabras_ram}"))

    def directiva(self, numero, fuente, nombre, operandos, direccion):
        if nombre in (".text", ".section", ".global", ".globl"):
            return direccion                     # sin efecto: todo va desde 0x0
        if nombre in (".equ", ".set"):
            if len(operandos) != 2:
                raise ErrorEnsamblado(f"{nombre} necesita: NOMBRE, VALOR")
            simbolo = operandos[0]
            if not re.fullmatch(r"[A-Za-z_.][\w.]*", simbolo):
                raise ErrorEnsamblado(f"nombre de constante invalido: '{simbolo}'")
            if simbolo in self.etiquetas:
                raise ErrorEnsamblado(f"'{simbolo}' ya es una etiqueta")
            if simbolo in self.definiciones:
                return direccion                 # gana el valor dado con -D
            try:
                self.constantes[simbolo] = self.valor(operandos[1], pasada=1)
            except SimboloPendiente as p:
                raise ErrorEnsamblado(
                    f"la constante '{simbolo}' usa '{p}', que no esta definido antes")
            return direccion
        if nombre == ".word":
            if not operandos:
                raise ErrorEnsamblado(".word necesita al menos un valor")
            self.lineas.append(Linea(numero, fuente, direccion, ".word", operandos, len(operandos)))
            return direccion + 4 * len(operandos)
        raise ErrorEnsamblado(f"directiva no soportada: {nombre}")

    def tamano(self, nombre, operandos):
        """Palabras que ocupa una instruccion. Solo li, la y call ocupan 2."""
        if nombre not in CONOCIDAS:
            raise ErrorEnsamblado(f"instruccion desconocida: '{nombre}'")
        if nombre in ("la", "call"):
            return 2
        if nombre == "li":
            if len(operandos) != 2:
                raise ErrorEnsamblado("li necesita: rd, valor")
            try:
                valor = a_32_bits(self.valor(operandos[1], pasada=1))
            except SimboloPendiente:
                return 2                         # depende de una etiqueta
            return len(self.expandir_li(valor))
        return 1

    # ------------------------------------------------------------------
    #  Pasada 2: codificacion
    # ------------------------------------------------------------------
    def pasada2(self):
        salida = []                              # (direccion, palabra, campos, linea)
        for linea in self.lineas:
            try:
                codificadas = self.codificar(linea)
                if len(codificadas) != linea.palabras:
                    raise ErrorEnsamblado("error interno: el tamano cambio entre pasadas")
                for k, (palabra, campos) in enumerate(codificadas):
                    salida.append((linea.direccion + 4 * k, palabra, campos, linea))
            except ErrorEnsamblado as e:
                self.error(linea.numero, linea.fuente, str(e))
        return salida

    def contar(self, operandos, n, forma):
        if len(operandos) != n:
            raise ErrorEnsamblado(f"se esperaban {n} operandos: {forma}")

    def memoria(self, texto):
        """'8(x6)' -> (8, 6).  '(x6)' -> (0, 6)."""
        m = OPERANDO_MEMORIA.match(texto.strip())
        if not m:
            raise ErrorEnsamblado(f"se esperaba offset(registro), por ejemplo 4(x6): '{texto}'")
        offset = m.group(1).strip()
        return (self.valor(offset, 2) if offset else 0), registro(m.group(2))

    def desplazamiento(self, destino, pc, bits_rango, que):
        """Distancia desde la instruccion (pc) hasta el destino."""
        off = self.valor(destino, 2) - pc
        limite = 1 << (bits_rango - 1)
        if off % 2:
            raise ErrorEnsamblado(f"el destino de un {que} debe ser par: {off}")
        return revisar_rango(off, -limite, limite - 2, f"desplazamiento de {que}")

    def expandir_li(self, valor):
        """li en una o dos instrucciones reales, igual que el ensamblador GNU."""
        hi, lo = partir_hi_lo(valor)
        if -2048 <= valor <= 2047:
            return [("addi", lo)]               # addi rd, x0, valor
        if lo == 0:
            return [("lui", hi)]                # lui rd, hi
        return [("lui", hi), ("addi", lo)]      # lui rd, hi ; addi rd, rd, lo

    # ------------------------------------------------------------------
    def codificar(self, linea):
        n = linea.nombre
        ops = linea.operandos
        pc = linea.direccion

        if n == ".word":
            return [((a_32_bits(self.valor(o, 2)) & 0xFFFFFFFF), "dato .word") for o in ops]

        if n in SHIFTS_DESACTIVADOS:
            self.advertencia(linea.numero, linea.fuente,
                             f"'{n}' se codifica, pero el Espino ejecuta los shifts como add")

        # ---------------- instrucciones reales ----------------
        if n in TIPO_R:
            self.contar(ops, 3, f"{n} rd, rs1, rs2")
            f3, f7 = TIPO_R[n]
            return [formato_r(OP_OP, registro(ops[0]), f3, registro(ops[1]), registro(ops[2]), f7)]

        if n in TIPO_I:
            self.contar(ops, 3, f"{n} rd, rs1, inmediato")
            return [formato_i(OP_OPIMM, registro(ops[0]), TIPO_I[n], registro(ops[1]),
                              imm12(self.valor(ops[2], 2)))]

        if n in TIPO_SHIFT:
            self.contar(ops, 3, f"{n} rd, rs1, desplazamiento")
            f3, f7 = TIPO_SHIFT[n]
            shamt = revisar_rango(self.valor(ops[2], 2), 0, 31, "cantidad de desplazamiento")
            return [formato_i(OP_OPIMM, registro(ops[0]), f3, registro(ops[1]), (f7 << 5) | shamt)]

        if n in CARGAS:
            self.contar(ops, 2, f"{n} rd, offset(rs1)")
            offset, rs1 = self.memoria(ops[1])
            return [formato_i(OP_LOAD, registro(ops[0]), CARGAS[n], rs1, imm12(offset))]

        if n in STORES:
            self.contar(ops, 2, f"{n} rs2, offset(rs1)")
            offset, rs1 = self.memoria(ops[1])
            return [formato_s(OP_STORE, STORES[n], rs1, registro(ops[0]), imm12(offset))]

        if n in SALTOS:
            self.contar(ops, 3, f"{n} rs1, rs2, etiqueta")
            off = self.desplazamiento(ops[2], pc, 13, "salto condicional")
            return [formato_b(OP_BRANCH, SALTOS[n], registro(ops[0]), registro(ops[1]), off)]

        if n in ("lui", "auipc"):
            self.contar(ops, 2, f"{n} rd, inmediato de 20 bits")
            imm = revisar_rango(self.valor(ops[1], 2), 0, 0xFFFFF, "inmediato de 20 bits")
            return [formato_u(OP_LUI if n == "lui" else OP_AUIPC, registro(ops[0]), imm)]

        if n == "jal":
            if len(ops) == 1:                    # jal etiqueta  ->  rd = ra
                rd, destino = 1, ops[0]
            else:
                self.contar(ops, 2, "jal rd, etiqueta")
                rd, destino = registro(ops[0]), ops[1]
            return [formato_j(OP_JAL, rd, self.desplazamiento(destino, pc, 21, "jal"))]

        if n == "jalr":
            if len(ops) == 1:                    # jalr rs1
                rd, imm, rs1 = 1, 0, registro(ops[0])
            elif len(ops) == 2 and "(" in ops[1]:
                rd = registro(ops[0])            # jalr rd, offset(rs1)
                imm, rs1 = self.memoria(ops[1])
            elif len(ops) == 2:
                rd, imm, rs1 = registro(ops[0]), 0, registro(ops[1])
            else:
                self.contar(ops, 3, "jalr rd, rs1, offset")
                rd, rs1, imm = registro(ops[0]), registro(ops[1]), self.valor(ops[2], 2)
            return [formato_i(OP_JALR, rd, 0b000, rs1, imm12(imm))]

        if n == "fence":
            return [(0x0FF0000F, "I fence iorw, iorw")]
        if n == "ecall":
            return [(0x00000073, "I ecall")]
        if n == "ebreak":
            return [(0x00100073, "I ebreak")]

        # ---------------- pseudo-instrucciones ----------------
        if n == "nop":
            self.contar(ops, 0, "nop")
            return [formato_i(OP_OPIMM, 0, 0b000, 0, 0)]

        if n == "li":
            self.contar(ops, 2, "li rd, valor")
            rd = registro(ops[0])
            valor = a_32_bits(self.valor(ops[1], 2))
            partes = self.expandir_li(valor)
            if linea.palabras == 2 and len(partes) == 1:
                hi, lo = partir_hi_lo(valor)     # se reservaron 2 en la pasada 1
                partes = [("lui", hi), ("addi", lo)]
            codigo = []
            for k, (instr, imm) in enumerate(partes):
                if instr == "lui":
                    codigo.append(formato_u(OP_LUI, rd, imm))
                else:
                    origen = 0 if k == 0 else rd
                    codigo.append(formato_i(OP_OPIMM, rd, 0b000, origen, imm))
            return codigo

        if n == "la":
            self.contar(ops, 2, "la rd, etiqueta")
            rd = registro(ops[0])
            hi, lo = partir_hi_lo(self.valor(ops[1], 2) - pc)   # relativo al pc
            return [formato_u(OP_AUIPC, rd, hi), formato_i(OP_OPIMM, rd, 0b000, rd, lo)]

        if n == "mv":
            self.contar(ops, 2, "mv rd, rs")
            return [formato_i(OP_OPIMM, registro(ops[0]), 0b000, registro(ops[1]), 0)]

        if n == "not":
            self.contar(ops, 2, "not rd, rs")
            return [formato_i(OP_OPIMM, registro(ops[0]), 0b100, registro(ops[1]), -1)]

        if n == "neg":
            self.contar(ops, 2, "neg rd, rs")
            return [formato_r(OP_OP, registro(ops[0]), 0b000, 0, registro(ops[1]), 0b0100000)]

        if n == "seqz":
            self.contar(ops, 2, "seqz rd, rs")
            return [formato_i(OP_OPIMM, registro(ops[0]), 0b011, registro(ops[1]), 1)]

        if n == "snez":
            self.contar(ops, 2, "snez rd, rs")
            return [formato_r(OP_OP, registro(ops[0]), 0b011, 0, registro(ops[1]), 0)]

        if n == "j":
            self.contar(ops, 1, "j etiqueta")
            return [formato_j(OP_JAL, 0, self.desplazamiento(ops[0], pc, 21, "salto"))]

        if n == "call":
            # Como en la especificacion: auipc ra, hi ; jalr ra, lo(ra).
            # Llega a cualquier direccion de 32 bits, no solo a +-1 MiB.
            self.contar(ops, 1, "call etiqueta")
            hi, lo = partir_hi_lo(self.valor(ops[0], 2) - pc)
            return [formato_u(OP_AUIPC, 1, hi), formato_i(OP_JALR, 1, 0b000, 1, lo)]

        if n == "jr":
            self.contar(ops, 1, "jr rs")
            return [formato_i(OP_JALR, 0, 0b000, registro(ops[0]), 0)]

        if n == "ret":
            self.contar(ops, 0, "ret")
            return [formato_i(OP_JALR, 0, 0b000, 1, 0)]

        if n in CONTRA_CERO:
            self.contar(ops, 2, f"{n} rs, etiqueta")
            real, invertido = CONTRA_CERO[n]
            rs = registro(ops[0])
            rs1, rs2 = (0, rs) if invertido else (rs, 0)
            off = self.desplazamiento(ops[1], pc, 13, "salto condicional")
            return [formato_b(OP_BRANCH, SALTOS[real], rs1, rs2, off)]

        if n in INVERTIDOS:
            self.contar(ops, 3, f"{n} rs1, rs2, etiqueta")
            off = self.desplazamiento(ops[2], pc, 13, "salto condicional")
            return [formato_b(OP_BRANCH, SALTOS[INVERTIDOS[n]],
                              registro(ops[1]), registro(ops[0]), off)]

        raise ErrorEnsamblado(f"instruccion desconocida: '{n}'")

    # ------------------------------------------------------------------
    def ensamblar(self, texto):
        # La pasada 2 corre aunque la 1 tenga errores, para informar todos
        # los problemas de una vez y no de a uno por cada intento.
        self.pasada1(texto)
        salida = self.pasada2()
        if self._errores:
            return None
        return salida


# =====================================================================
#  Archivos de salida
# =====================================================================

def escribir_hex(salida, ruta):
    with open(ruta, "w", newline="\n") as f:
        for _, palabra, _, _ in salida:
            f.write(f"{palabra:08x}\n")


def escribir_listado(salida, ruta, ens):
    with open(ruta, "w", newline="\n") as f:
        f.write("DIR   PALABRA   CAMPOS (formato y bits de cada campo)"
                "                                    LINEA  FUENTE\n")
        anterior = None
        for direccion, palabra, campos, linea in salida:
            fuente = linea.fuente.strip() if linea is not anterior else ""
            f.write(f"{direccion:04x}  {palabra:08x}  {campos:<86}  "
                    f"{linea.numero:>5}  {fuente}\n")
            anterior = linea
        f.write("\nETIQUETAS\n")
        for nombre, direccion in sorted(ens.etiquetas.items(), key=lambda x: x[1]):
            f.write(f"  {direccion:04x}  {nombre}\n")
        f.write("\nCONSTANTES\n")
        for nombre, valor in ens.constantes.items():
            f.write(f"  {nombre} = {valor} (0x{valor & 0xFFFFFFFF:x})\n")


def leer_definiciones(lista):
    definiciones = {}
    for d in lista or []:
        if "=" not in d:
            raise SystemExit(f"error: -D necesita NOMBRE=VALOR (recibido '{d}')")
        nombre, texto = d.split("=", 1)
        try:
            definiciones[nombre.strip()] = Evaluador({}, {}, 2).evaluar(texto)
        except ErrorEnsamblado as e:
            raise SystemExit(f"error en -D {d}: {e}")
    return definiciones


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Ensamblador RV32E para el Espino Core (Pochoco SoC)")
    p.add_argument("entrada", help="archivo assembly, por ejemplo sw/game.s")
    p.add_argument("-o", "--salida", required=True, help="archivo .hex de salida")
    p.add_argument("-l", "--listado", help="archivo de listado opcional")
    p.add_argument("-D", dest="definiciones", action="append", metavar="NOMBRE=VALOR",
                   help="redefine una constante .equ")
    p.add_argument("--palabras", type=int, default=512,
                   help="tamano de la RAM en palabras (por defecto 512)")
    args = p.parse_args(argv)

    with open(args.entrada, encoding="utf-8-sig") as f:
        texto = f.read()

    ens = Ensamblador(leer_definiciones(args.definiciones), args.palabras)
    salida = ens.ensamblar(texto)

    for a in ens.advertencias:
        print(f"advertencia, {a}", file=sys.stderr)

    if salida is None:
        for e in ens.errores:
            print(f"ERROR, {e}", file=sys.stderr)
        print(f"\n{len(ens.errores)} error(es). No se escribio {args.salida}.", file=sys.stderr)
        return 1

    escribir_hex(salida, args.salida)
    if args.listado:
        escribir_listado(salida, args.listado, ens)

    print(f"{args.entrada} -> {args.salida}: {len(salida)} palabras "
          f"({4 * len(salida)} bytes de {4 * args.palabras}), "
          f"{len(ens.etiquetas)} etiquetas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
