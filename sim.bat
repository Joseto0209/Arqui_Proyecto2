@echo off
REM ============================================================
REM  sim.bat - Compila y corre un testbench de la carpeta tb\
REM
REM  Uso:  sim tb_periph
REM        sim tb_soc
REM        sim tb_game
REM
REM  Junta todos los modulos de rtl\ (incluido rtl\espino_core\),
REM  el modelo de simulacion de la RAM de la iCE40 y el testbench.
REM  Si la compilacion falla, NO corre la simulacion: asi nunca se
REM  ejecuta un .vvp viejo por error (la trampa clasica del P1).
REM ============================================================

setlocal

if "%~1"=="" (
    echo.
    echo   Uso: sim NOMBRE_DEL_TESTBENCH
    echo.
    echo   Testbenches disponibles:
    dir /b tb\tb_*.v
    echo.
    exit /b 1
)

if not exist "tb\%~1.v" (
    echo.
    echo   No existe tb\%~1.v
    echo.
    exit /b 1
)

if not exist build mkdir build

REM La redireccion va al inicio para no dejar espacios al final de linea
> build\srcs.txt dir /b /s rtl\*.v
>>build\srcs.txt echo tb\sb_ram40_4k.v
>>build\srcs.txt echo tb\%~1.v

iverilog -g2012 -o build\%~1.vvp -s %~1 -c build\srcs.txt
if errorlevel 1 (
    echo.
    echo   COMPILACION FALLIDA. Revisa los errores de arriba.
    echo   NO se ejecuta la simulacion.
    echo.
    exit /b 1
)

vvp build\%~1.vvp

endlocal
