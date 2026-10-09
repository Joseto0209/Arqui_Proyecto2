# Copyright 2026 Universidad de los Andes.
# Licensed under the Solderpad Hardware License, Version 0.51 (the "License");
# you may not use this file except in compliance with the License.
# SPDX-License-Identifier: SHL-0.51
#
# Course: Arquitectura de Computadores (2026)
#
# Authors:
# - Nicolás Villegas <navillegas@miuandes.cl>   (flujo original del Pochoco)
#
# Adaptado para el Proyecto 2 (juego de reflejos): el top ahora es
# game_top, el programa se ensambla con asm/asm.py y hay objetivos de
# simulacion. En Windows, build.bat y sim.bat hacen lo mismo.
#
#   make            ensambla, sintetiza, rutea y graba la FPGA
#   make hex        solo regenera sw/game.hex desde sw/game.s
#   make bin        todo menos grabar
#   make test       pruebas del ensamblador y las tres simulaciones
#   make sim TB=tb_game
#   make clean

# Configuration
TOP   := game_top
PCF   := goboard.pcf
PY    ?= python3
BUILD := build

# RTL Sources (rtl/ y rtl/espino_core/)
SRC  := $(wildcard rtl/*.v rtl/espino_core/*.v)

# Build Targets
HEX  := sw/game.hex
JSON := $(BUILD)/$(TOP).json
ASC  := $(BUILD)/$(TOP).asc
BIN  := $(BUILD)/$(TOP).bin

# Simulacion: el juego con una decima de 2.500 ciclos (1000 veces mas rapido)
SIM_SRC := $(SRC) tb/sb_ram40_4k.v

.PHONY: all hex bin prog test sim clean

# Default target
all: prog

$(BUILD):
	mkdir -p $(BUILD)

# Step 0: Assemble the game with the group's assembler
hex: $(HEX)
$(HEX): sw/game.s asm/asm.py | $(BUILD)
	$(PY) asm/asm.py sw/game.s -o $(HEX) -l $(BUILD)/game.lst

# Step 1: Synthesis using Yosys
$(JSON): $(SRC) $(HEX) | $(BUILD)
	yosys -p "read_verilog $(SRC); synth_ice40 -top $(TOP) -dffe_min_ce_use 4 -json $(JSON); stat"

# Step 2: Place and Route using NextPNR
$(ASC): $(JSON) $(PCF)
	nextpnr-ice40 --hx1k --package vq100 --freq 25 --json $(JSON) --pcf $(PCF) --asc $(ASC)

# Step 3: Bitstream Generation
bin: $(BIN)
$(BIN): $(ASC)
	icepack $(ASC) $(BIN)

# Step 4: Flash the Board
prog: $(BIN)
	iceprog $(BIN)

# Programas que usan las simulaciones
$(BUILD)/prueba_cpu.hex: sw/prueba_cpu.s asm/asm.py | $(BUILD)
	$(PY) asm/asm.py sw/prueba_cpu.s -o $@
$(BUILD)/game_sim.hex: sw/game.s asm/asm.py | $(BUILD)
	$(PY) asm/asm.py sw/game.s -o $@ -D CICLOS_DECIMA=2500

# Una simulacion: make sim TB=tb_game
TB ?= tb_game
sim: $(BUILD)/prueba_cpu.hex $(BUILD)/game_sim.hex
	iverilog -g2012 -o $(BUILD)/$(TB).vvp -s $(TB) $(SIM_SRC) tb/$(TB).v
	vvp -n $(BUILD)/$(TB).vvp

# Todas las pruebas
test: $(BUILD)/prueba_cpu.hex $(BUILD)/game_sim.hex
	$(PY) asm/pruebas/probar_asm.py
	$(MAKE) --no-print-directory sim TB=tb_periph
	$(MAKE) --no-print-directory sim TB=tb_soc
	$(MAKE) --no-print-directory sim TB=tb_game

# Clean up generated files
clean:
	rm -rf $(BUILD)
