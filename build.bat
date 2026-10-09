@echo off
REM ============================================================
REM  build.bat - Ensambla el juego, sintetiza, rutea y graba
REM
REM  Uso:  build
REM
REM  [1/5] asm.py:   sw\game.s     -> sw\game.hex
REM  [2/5] Yosys:    rtl\*.v        -> build\game_top.json
REM  [3/5] nextpnr:  .json + .pcf   -> build\game_top.asc
REM  [4/5] icepack:  .asc           -> build\game_top.bin
REM  [5/5] iceprog:  .bin           -> FPGA
REM
REM  Si una etapa falla se detiene, para no grabar un bitstream
REM  viejo por accidente.
REM ============================================================

setlocal enabledelayedexpansion

if not exist build mkdir build

echo.
echo   [1/5] Ensamblando sw\game.s ...
python asm\asm.py sw\game.s -o sw\game.hex -l build\game.lst
if errorlevel 1 (
    echo   FALLO EL ENSAMBLADO. Se detiene aqui.
    exit /b 1
)

REM Lista de fuentes con barras normales, para el script de Yosys
set SRCS=
for %%f in (rtl\*.v)             do set SRCS=!SRCS! rtl/%%~nxf
for %%f in (rtl\espino_core\*.v) do set SRCS=!SRCS! rtl/espino_core/%%~nxf

> build\game_top.ys echo read_verilog!SRCS!
>>build\game_top.ys echo synth_ice40 -top game_top -dffe_min_ce_use 4 -json build/game_top.json
>>build\game_top.ys echo tee -o build/stat.txt stat

echo.
echo   [2/5] Sintesis con Yosys ...
yosys -q -s build\game_top.ys
if errorlevel 1 (
    echo   FALLO LA SINTESIS. Se detiene aqui.
    exit /b 1
)
findstr /C:"SB_LUT4" /C:"SB_RAM40_4K" build\stat.txt

echo.
echo   [3/5] Place and route con nextpnr ...
nextpnr-ice40 --hx1k --package vq100 --freq 25 --json build/game_top.json --pcf goboard.pcf --asc build/game_top.asc 2> build\pnr.log
if errorlevel 1 (
    echo   FALLO EL PLACE AND ROUTE. Revisa build\pnr.log
    exit /b 1
)
findstr /C:"ICESTORM_LC:" /C:"PASS at" /C:"FAIL at" build\pnr.log

echo.
echo   [4/5] Generando el bitstream ...
icepack build/game_top.asc build/game_top.bin
if errorlevel 1 (
    echo   FALLO ICEPACK. Se detiene aqui.
    exit /b 1
)

echo.
echo   [5/5] Grabando la FPGA ...
iceprog build/game_top.bin
if errorlevel 1 (
    echo.
    echo   FALLO LA GRABACION. Revisa que la placa este conectada: iceprog -t
    exit /b 1
)

echo.
echo   LISTO. Aprieta cualquier boton para empezar a jugar.
echo.

endlocal
