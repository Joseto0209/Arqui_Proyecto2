# Proyecto 2 — Juego de reflejos sobre Pochoco SoC

**ICC3302 Arquitectura de Computadores** · Universidad de los Andes · 2026-2
Profesor: Jorge Gómez Mir

**Integrantes:** José Tomás Arévalo · Santiago Arenas · Danna Collazos

Juego de reflejos escrito en assembly RV32E para el **Espino Core**, dentro del
**Pochoco SoC**, sobre la FPGA Lattice iCE40 HX1K de la Nandland Go Board. El
programa se traduce a código máquina con un **ensamblador propio** escrito en
Python (`asm/asm.py`), sin usar ningún ensamblador RISC-V externo.

El repositorio parte de un fork de
[nic0villegasc/pochoco_soc](https://github.com/nic0villegasc/pochoco_soc). Los
cambios al hardware son dos: un **contador de ciclos** legible en `0x8000_000C` y
el módulo superior **`rtl/game_top.v`**.

---

## Cómo se juega

| Momento | LEDs | Display |
|---|---|---|
| Al encender: **cualquier botón empieza** | apagados | `00` |
| Inicio de cada ronda (3 s) | los 4 encendidos | tiempo de la ronda anterior |
| Esperando la reacción | **solo el LED objetivo** | tiempo de la ronda anterior |
| Acierto | — | tiempo en **décimas de segundo** (`23` = 2,3 s) |
| Botón equivocado (1 s, se repite la ronda) | apagados | `EE` |
| Tras la ronda 10: su tiempo (2 s) | apagados | tiempo de la ronda 10 |
| Fin: **cualquier botón empieza otra partida** | alternan `1001` / `0110` | **promedio** de las 10 rondas |

El botón *i* corresponde al LED *i* (bit *i* de los registros de botones y LEDs):

| Botón | Bit |
|---|---|
| Superior izquierdo | 0 |
| Inferior izquierdo | 1 |
| Superior derecho | 2 |
| Inferior derecho | 3 |

Las rondas correctas se conservan aunque haya errores. El tiempo máximo que se
muestra es 9,9 s (`99`). El promedio es el de los diez valores mostrados,
redondeado a la décima más cercana.

---

## Qué hay en el repositorio

```
rtl/
  game_top.v               top del proyecto (lo que se sintetiza)
  pochoco_soc.v            SoC: Espino + RAM + periféricos + SPI
  pochoco_periph.v         LEDs, botones, displays y contador de ciclos (modificado)
  pochoco_ram.v, pochoco_spi_slave.v
  espino_core/             el procesador RV32E (sin cambios)
sw/
  game.s                   el juego en assembly
  game.hex                 el juego ensamblado (lo que carga la RAM)
  prueba_cpu.s             autoprueba de 16 pruebas del procesador
  blink.s, 7seg.s, buttons_leds.s   ejemplos originales del Pochoco
asm/
  asm.py                   el ensamblador
  pruebas/                 pruebas del ensamblador (32 casos)
tb/
  tb_periph.v              periférico y contador de ciclos (15 pruebas)
  tb_soc.v                 SoC completo corriendo prueba_cpu.s
  tb_game.v                juego completo con un jugador simulado (28 pruebas)
  sb_ram40_4k.v            modelo de la RAM de la iCE40, solo para simular
build.bat                  Windows: ensambla, sintetiza y graba
sim.bat, waves.bat         Windows: simular y abrir GTKWave
Makefile                   Linux / macOS: lo mismo que los .bat
goboard.pcf                pines de la Go Board
demostracion.txt           guía de comandos para la demostración
```

La carpeta `build/` se genera al compilar y no se sube al repositorio.

---

## 1. Instalación

1. **OSS CAD Suite** desde los [releases](https://github.com/YosysHQ/oss-cad-suite-build/releases)
   (en Windows, `oss-cad-suite-windows-x64-<fecha>.tgz`). Trae Yosys, nextpnr,
   icepack, iceprog, Icarus Verilog y GTKWave.
2. **Python 3.8 o superior** desde [python.org](https://www.python.org). En Windows,
   marcar *"Add python.exe to PATH"* al instalar. El ensamblador no usa
   bibliotecas externas.
3. **Git**, y clonar el repositorio:

```
git clone https://github.com/Joseto0209/Arqui_Proyecto2.git
```

4. **Solo en Windows, una vez:** con [Zadig](https://zadig.akeo.ie), cambiar el
   driver de la **Interface 0** de la placa a **WinUSB** (Options → List All
   Devices → Interface 0 → WinUSB → Replace Driver). Sin esto, `iceprog` no
   encuentra la placa.

---

## 2. Abrir la terminal

En Windows, todas las herramientas existen solo dentro de la terminal de
OSS CAD Suite. Se abre con doble clic en `oss-cad-suite\start.bat`, y cada línea
empieza con `[OSS CAD Suite]`. Después hay que ir a la carpeta del proyecto:

```
cd /d C:\ruta\al\proyecto
```

En Linux y macOS: `source oss-cad-suite/environment`.

---

## 3. Regenerar `game.hex` desde `game.s`

```
python asm/asm.py sw/game.s -o sw/game.hex
```

Debe responder:

```
sw/game.s -> sw/game.hex: 184 palabras (736 bytes de 2048), 34 etiquetas
```

Con `-l` genera además un **listado** con la dirección, la palabra, los campos de
cada instrucción en binario y la línea original:

```
python asm/asm.py sw/game.s -o sw/game.hex -l build/game.lst
```

### Cambiar una constante del juego

Las constantes están al principio de `sw/game.s`. Por ejemplo, para que la fase
inicial dure 5 segundos:

```
.equ DECIMAS_INICIO,   50                # fase con los 4 LEDs: 5,0 s
```

Después se regenera `game.hex` y se vuelve a programar (sección 4). Las
cantidades de ciclos se calculan solas a partir de las décimas.

| Constante | Valor | Qué controla |
|---|---|---|
| `FRECUENCIA` | 25000000 | reloj de la placa, en Hz |
| `CICLOS_DECIMA` | `FRECUENCIA / 10` | ciclos que forman una décima (2.500.000) |
| `DECIMAS_INICIO` | 30 | fase con los 4 LEDs (3,0 s) |
| `DECIMAS_ERROR` | 10 | duración del `EE` (1,0 s) |
| `DECIMAS_FINAL` | 20 | tiempo de la ronda 10 antes del promedio (2,0 s) |
| `DECIMAS_PARPADEO` | 5 | parpadeo de la pantalla final (0,5 s) |
| `DECIMAS_TOPE` | 99 | máximo que se muestra (9,9 s) |
| `RONDAS` | 10 | rondas correctas por partida |

También se puede cambiar una constante sin editar el archivo, con `-D`:

```
python asm/asm.py sw/game.s -o sw/game.hex -D RONDAS=5
```

---

## 4. Sintetizar y programar la FPGA

### Windows: un solo comando

```
build
```

Hace los cinco pasos en orden y se detiene si alguno falla:

| Paso | Herramienta | Qué debe salir |
|---|---|---|
| 1/5 | `asm.py` | `sw/game.s -> sw/game.hex: 184 palabras ...` |
| 2/5 | Yosys | cerca de 1010 `SB_LUT4` y 12 `SB_RAM40_4K` |
| 3/5 | nextpnr | `ICESTORM_LC: ~1180/1280 92%` y `PASS at 25.00 MHz` |
| 4/5 | icepack | nada (sin errores) |
| 5/5 | iceprog | `VERIFY OK` y `LISTO` |

Después de grabar, se aprieta cualquier botón para empezar a jugar.

### Los mismos pasos, uno por uno

```
python asm/asm.py sw/game.s -o sw/game.hex
yosys -p "read_verilog rtl/game_top.v rtl/pochoco_soc.v rtl/pochoco_periph.v rtl/pochoco_ram.v rtl/pochoco_spi_slave.v rtl/espino_core/espino_alu.v rtl/espino_core/espino_controller.v rtl/espino_core/espino_core.v rtl/espino_core/espino_decoder.v rtl/espino_core/espino_id_stage.v rtl/espino_core/espino_if_stage.v rtl/espino_core/espino_load_store_unit.v rtl/espino_core/espino_register_file.v; synth_ice40 -top game_top -dffe_min_ce_use 4 -json build/game_top.json; stat"
nextpnr-ice40 --hx1k --package vq100 --freq 25 --json build/game_top.json --pcf goboard.pcf --asc build/game_top.asc
icepack build/game_top.asc build/game_top.bin
iceprog build/game_top.bin
```

Antes del primero, la carpeta `build` debe existir (`mkdir build`). En Windows,
el comando de Yosys necesita la lista completa de archivos, porque CMD no
expande `rtl/*.v`.

### Linux y macOS

```
make          # ensambla, sintetiza, rutea y graba
make bin      # todo menos grabar
make hex      # solo regenera sw/game.hex
```

---

## 5. Simulación y pruebas

Todas las pruebas imprimen una línea `PASS` o `FAIL` por caso y terminan con un
resumen. En Windows:

| Qué se prueba | Comandos | Resultado esperado |
|---|---|---|
| Ensamblador | `python asm/pruebas/probar_asm.py` | `Pruebas aprobadas: 32/32` |
| Periférico y contador de ciclos | `sim tb_periph` | `Pruebas aprobadas: 15/15` |
| Procesador completo | `python asm/asm.py sw/prueba_cpu.s -o build/prueba_cpu.hex` y luego `sim tb_soc` | `display = 10` (16 pruebas) y `3/3` |
| Juego completo (tarda ~1 minuto) | `python asm/asm.py sw/game.s -o build/game_sim.hex -D CICLOS_DECIMA=2500` y luego `sim tb_game` | `Pruebas aprobadas: 28/28` |

En Linux y macOS, `make test` corre las cuatro.

Para ver las ondas de una simulación: `waves tb_game` (o `gtkwave build/tb_game.vcd`).

**Por qué `-D CICLOS_DECIMA=2500` en la simulación del juego:** con el valor
real, cada ronda serían 75 millones de ciclos solo en la fase inicial. Con una
décima de 2.500 ciclos, todo ocurre 1000 veces más rápido y el programa es
exactamente el mismo; solo cambia la constante.

---

## 6. El ensamblador

`asm/asm.py` lee el archivo en **dos pasadas**: la primera asigna una dirección a
cada línea y registra las etiquetas; la segunda codifica cada instrucción en sus
32 bits, ya con todas las etiquetas conocidas.

| Elemento | Sintaxis |
|---|---|
| Comentarios | `# hasta el final de la línea` |
| Etiquetas | `nombre:` (también en la misma línea que una instrucción) |
| Registros | `x0`–`x15` y los nombres ABI: `zero ra sp gp tp t0-t2 s0/fp s1 a0-a5` |
| Inmediatos | decimal, `0x` hexadecimal, `0b` binario, negativos y expresiones con `+ - * / ( )` |
| Directivas | `.equ`/`.set NOMBRE, valor` · `.word v1, v2, ...` · `.text` `.section` `.global` (sin efecto) |
| Instrucciones | todo RV32E: `add sub sll slt sltu xor srl sra or and`, `addi slti sltiu xori ori andi slli srli srai`, `lb lh lw lbu lhu`, `sb sh sw`, `beq bne blt bge bltu bgeu`, `lui auipc jal jalr`, `fence ecall ebreak` |
| Pseudo-instrucciones | `li la mv not neg seqz snez nop j jr call ret beqz bnez bltz bgez blez bgtz bgt ble bgtu bleu` |

Valida registros (solo `x0`–`x15`), rangos de inmediatos y desplazamientos,
etiquetas repetidas o no definidas, instrucciones desconocidas, cantidad de
operandos y el tamaño de la RAM (512 palabras). Si hay errores, no escribe el
`.hex` y los informa todos con su número de línea. Los shifts se codifican, pero
el ensamblador avisa que el Espino los ejecuta como `add`.

Las pruebas comparan su salida, palabra por palabra, con los `.hex` oficiales del
Pochoco y con una referencia generada una vez con el ensamblador GNU de RISC-V
(`asm/pruebas/todas.hex`).

---

## 7. Cambios al RTL

**Contador de ciclos** (`rtl/pochoco_periph.v`): registro de 32 bits que suma 1 en
cada flanco del reloj de 25 MHz. Es de solo lectura, en `0x8000_000C`.

| Magnitud | Valor |
|---|---|
| 1 ciclo | 40 ns |
| 1 décima de segundo | 2.500.000 ciclos |
| 3 segundos | 75.000.000 ciclos |
| Desborde del contador | 2³² ciclos = 171,8 s |

El juego solo usa diferencias (`ahora − inicio`). La resta sin signo de 32 bits
es correcta aunque el contador dé la vuelta entre las dos lecturas.

**`rtl/game_top.v`:** instancia `pochoco_soc` con `MemFile = "sw/game.hex"` y
conecta los pines de la Go Board.

**Recursos:** el Pochoco original usa 1082 de 1280 celdas lógicas (84 %); con el
contador, cerca de 1180 (92 %), con una frecuencia máxima de alrededor de
40 MHz frente a los 25 MHz del reloj.

---

## 8. Si algo falla

| Síntoma | Causa y solución |
|---|---|
| `"yosys" no se reconoce como comando` | La terminal no es la de OSS CAD Suite. Abrir `start.bat`. |
| `"python" no se reconoce` | Instalar Python marcando *Add to PATH* y abrir otra terminal. |
| `Can't find iCE FTDI USB device` | Desconectar y reconectar el USB. La primera vez, aplicar Zadig (sección 1). |
| `COMPILACION FALLIDA` en `sim` | Revisar el error de iverilog. El `.bat` no corre la simulación vieja. |
| `ERROR, linea N: ...` del ensamblador | El mensaje indica la línea de `game.s` y el problema. No se escribe `game.hex`. |
| `Not enough words in the file` | Aviso inofensivo: el programa ocupa menos que las 512 palabras de la RAM. |
| La placa no hace nada al encender | Es lo esperado: espera un botón para empezar (display `00`). |
| `cd` no cambia de carpeta | Falta el `/d`: `cd /d C:\ruta\completa`. |

---

## Créditos

- Pochoco SoC y Espino Core: Nicolás Villegas, Universidad de los Andes
  ([pochoco_soc](https://github.com/nic0villegasc/pochoco_soc)), bajo la licencia
  Solderpad Hardware License 0.51. Se conservan sus avisos de copyright.
- Juego, ensamblador, contador de ciclos, `game_top` y pruebas: el grupo.
