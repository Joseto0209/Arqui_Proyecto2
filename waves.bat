@echo off
REM ============================================================
REM  waves.bat - Abre en GTKWave las ondas de un testbench
REM
REM  Uso:  waves tb_soc
REM
REM  Primero hay que correr la simulacion: sim tb_soc
REM ============================================================

if "%~1"=="" (
    echo   Uso: waves NOMBRE_DEL_TESTBENCH
    exit /b 1
)

if not exist "build\%~1.vcd" (
    echo   No existe build\%~1.vcd. Corre primero: sim %~1
    exit /b 1
)

gtkwave build\%~1.vcd
