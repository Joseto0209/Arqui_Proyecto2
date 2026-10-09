// tb_periph.v
// Testbench de pochoco_periph con el contador de ciclos agregado.
//
// Maneja el bus del periferico igual que lo haria la LSU del Espino
// (sel, req, we, addr, wdata) y revisa cada registro del mapa:
//
//   0x00  display   escritura
//   0x04  LEDs      escritura
//   0x08  botones   lectura
//   0x0C  contador  lectura (nuevo)
//
// Protocolo del bus: las senales se ponen en el flanco de bajada y el
// periferico las toma en el flanco de subida siguiente. La lectura
// queda registrada en rdata_o y se revisa en el flanco de bajada
// posterior.
//
// Correr (desde la raiz del repo):
//   iverilog -g2012 -o build/tb_periph.vvp -s tb_periph rtl/pochoco_periph.v tb/tb_periph.v
//   vvp build/tb_periph.vvp

`timescale 1ns/1ps

module tb_periph;

  reg         clk = 1'b0;
  reg         rst_ni = 1'b0;
  reg         sel = 1'b0, req = 1'b0, we = 1'b0;
  reg  [7:0]  addr = 8'h00;
  reg  [31:0] wdata = 32'h0;
  reg  [3:0]  btn = 4'b0000;
  wire [31:0] rdata;
  wire [3:0]  leds;
  wire [6:0]  seg1, seg2;

  pochoco_periph dut (
    .clk_i   (clk),
    .rst_ni  (rst_ni),
    .sel_i   (sel),
    .req_i   (req),
    .we_i    (we),
    .addr_i  (addr),
    .wdata_i (wdata),
    .rdata_o (rdata),
    .leds_o  (leds),
    .btn_i   (btn),
    .seg1_o  (seg1),
    .seg2_o  (seg2)
  );

  // Reloj de 25 MHz: periodo de 40 ns
  always #20 clk = ~clk;

  integer pasadas = 0;
  integer total   = 0;

  task revisar(input condicion, input [8*64-1:0] etiqueta);
    begin
      total = total + 1;
      if (condicion) begin
        pasadas = pasadas + 1;
        $display("PASS %0s", etiqueta);
      end else begin
        $display("FAIL %0s", etiqueta);
      end
    end
  endtask

  // Escritura de un ciclo en el bus
  task escribir(input [7:0] a, input [31:0] d);
    begin
      @(negedge clk); sel = 1; req = 1; we = 1; addr = a; wdata = d;
      @(negedge clk); sel = 0; req = 0; we = 0;
    end
  endtask

  // Lectura de un ciclo en el bus
  task leer(input [7:0] a, output [31:0] d);
    begin
      @(negedge clk); sel = 1; req = 1; we = 0; addr = a;
      @(negedge clk); d = rdata; sel = 0; req = 0;
    end
  endtask

  reg [31:0] v1, v2, v3;
  integer espera;

  initial begin
    $dumpfile("build/tb_periph.vcd");
    $dumpvars(0, tb_periph);

    // --- Reset ---
    repeat (5) @(negedge clk);
    revisar(dut.cycle_q == 32'd0, "el contador vale 0 durante el reset");
    rst_ni = 1'b1;

    // --- Display: 0x5A muestra 5 a la izquierda y A a la derecha ---
    escribir(8'h00, 32'h0000_005A);
    revisar(seg1 == 7'b1101101, "display izquierdo muestra 5");
    revisar(seg2 == 7'b1110111, "display derecho muestra A");

    // --- LEDs: solo se guardan los 4 bits bajos ---
    escribir(8'h04, 32'h0000_0005);
    revisar(leds == 4'b0101, "LEDs = 0101");
    escribir(8'h04, 32'hFFFF_FFF8);
    revisar(leds == 4'b1000, "LEDs ignora los bits altos");

    // --- Botones ---
    btn = 4'b0100;
    leer(8'h08, v1);
    revisar(v1 == 32'h0000_0004, "lectura de botones = 0100");
    btn = 4'b0000;
    leer(8'h08, v1);
    revisar(v1 == 32'h0000_0000, "lectura de botones sueltos = 0000");

    // --- Contador: avanza 1 por ciclo ---
    // Dos lecturas seguidas estan separadas por 2 flancos de subida
    // (cada lectura ocupa un ciclo completo del bus).
    leer(8'h0C, v1);
    leer(8'h0C, v2);
    revisar(v2 - v1 == 32'd2, "dos lecturas seguidas difieren en 2 ciclos");

    // Con N ciclos extra entre lecturas, la diferencia es N + 2
    espera = 1000;
    leer(8'h0C, v1);
    repeat (espera) @(negedge clk);
    leer(8'h0C, v2);
    revisar(v2 - v1 == espera + 2, "1000 ciclos de espera se miden como 1002");

    // El valor leido coincide con los ciclos transcurridos desde el reset
    revisar(v2 > 32'd1000 && v2 < 32'd1100, "el contador cuenta desde que termina el reset");

    // --- Escribir en 0x0C no altera el contador ---
    leer(8'h0C, v1);
    escribir(8'h0C, 32'h1234_5678);
    leer(8'h0C, v2);
    revisar(v2 - v1 == 32'd4, "escribir en el contador no lo modifica");
    revisar(leds == 4'b1000 && seg2 == 7'b1110111,
            "escribir en el contador no toca LEDs ni display");

    // --- Desborde: la resta sin signo sigue funcionando ---
    // Se fuerza el contador cerca del maximo para no simular 2^32 ciclos.
    @(negedge clk);
    force dut.cycle_q = 32'hFFFF_FFF0;
    @(negedge clk);
    release dut.cycle_q;
    leer(8'h0C, v1);
    repeat (40) @(negedge clk);
    leer(8'h0C, v2);
    revisar(v2 < v1, "el contador dio la vuelta (fin < inicio)");
    revisar(v2 - v1 == 32'd42, "la resta sin signo mide 42 ciclos a traves del desborde");

    // --- Offset sin uso ---
    leer(8'h10, v3);
    revisar(v3 == 32'h0, "un offset sin registro se lee como 0");

    $display("");
    $display("Pruebas aprobadas: %0d/%0d", pasadas, total);
    if (pasadas == total)
      $display("RESULTADO: el periferico y el contador de ciclos funcionan.");
    else
      $display("RESULTADO: hay pruebas que fallaron.");
    $finish;
  end

endmodule
