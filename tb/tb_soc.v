// tb_soc.v
// Testbench del sistema completo: game_top -> Pochoco SoC -> Espino.
//
// Carga un programa (.hex hecho con asm/asm.py) en la RAM del SoC y lo
// deja correr. Igual que en las diapositivas del curso, el testbench
// observa solo los puertos del top: lee los LEDs y decodifica los pines
// de los displays de vuelta a hexadecimal, como lo veria una persona
// mirando la placa.
//
// Por defecto corre sw/prueba_cpu.s (autoprueba de 16 pruebas). Al
// terminar, ese programa deja:
//   LEDs 1111 y display 10  -> todas las pruebas pasaron
//   LEDs 0101 y display N   -> fallo la prueba N
//
// Correr (desde la raiz del repo):
//   python asm/asm.py sw/prueba_cpu.s -o build/prueba_cpu.hex
//   sim tb_soc

`timescale 1ns/1ps

module tb_soc;

  parameter HEX = "build/prueba_cpu.hex";

  reg  clk = 1'b0;
  always #20 clk = ~clk;                      // 25 MHz

  reg  [3:0] botones = 4'b0000;
  wire [3:0] leds;
  wire s1a, s1b, s1c, s1d, s1e, s1f, s1g;
  wire s2a, s2b, s2c, s2d, s2e, s2f, s2g;

  game_top #(.MemFile(HEX)) dut (
    .i_Clk        (clk),
    .o_LED        (leds),
    .i_Switch     (botones),
    .o_Segment1_A (s1a), .o_Segment1_B (s1b), .o_Segment1_C (s1c), .o_Segment1_D (s1d),
    .o_Segment1_E (s1e), .o_Segment1_F (s1f), .o_Segment1_G (s1g),
    .o_Segment2_A (s2a), .o_Segment2_B (s2b), .o_Segment2_C (s2c), .o_Segment2_D (s2d),
    .o_Segment2_E (s2e), .o_Segment2_F (s2f), .o_Segment2_G (s2g),
    .i_SPI_SCLK   (1'b0),
    .i_SPI_MOSI   (1'b0),
    .i_SPI_CS_n   (1'b1),
    .o_SPI_MISO   ()
  );

  // ---------------------------------------------------------------
  // Pines de un display (activos en bajo) -> digito hexadecimal.
  // Devuelve 16 si el patron no corresponde a ningun digito.
  // ---------------------------------------------------------------
  function [4:0] digito(input g, f, e, d, c, b, a);
    reg [6:0] seg;
    begin
      seg = ~{g, f, e, d, c, b, a};           // 1 = segmento encendido
      case (seg)
        7'b0111111: digito = 5'h0;  7'b0000110: digito = 5'h1;
        7'b1011011: digito = 5'h2;  7'b1001111: digito = 5'h3;
        7'b1100110: digito = 5'h4;  7'b1101101: digito = 5'h5;
        7'b1111101: digito = 5'h6;  7'b0000111: digito = 5'h7;
        7'b1111111: digito = 5'h8;  7'b1101111: digito = 5'h9;
        7'b1110111: digito = 5'hA;  7'b1111100: digito = 5'hB;
        7'b0111001: digito = 5'hC;  7'b1011110: digito = 5'hD;
        7'b1111001: digito = 5'hE;  7'b1110001: digito = 5'hF;
        default:    digito = 5'h10;
      endcase
    end
  endfunction

  wire [4:0] izq = digito(s1g, s1f, s1e, s1d, s1c, s1b, s1a);
  wire [4:0] der = digito(s2g, s2f, s2e, s2d, s2c, s2b, s2a);
  wire [7:0] display = {izq[3:0], der[3:0]};

  integer pasadas = 0, total = 0, ciclos = 0;
  integer bucle1, bucle2;

  task revisar(input condicion, input [8*64-1:0] etiqueta);
    begin
      total = total + 1;
      if (condicion) begin pasadas = pasadas + 1; $display("PASS %0s", etiqueta); end
      else                                         $display("FAIL %0s", etiqueta);
    end
  endtask

  always @(posedge clk) ciclos = ciclos + 1;

  initial begin
    $dumpfile("build/tb_soc.vcd");
    $dumpvars(0, tb_soc);

    // Espera a que el programa termine (LEDs 1111 o 0101), con limite
    wait ((leds == 4'b1111 || leds == 4'b0101) || ciclos > 200000);
    repeat (5) @(posedge clk);

    $display("Programa: %0s, termino en %0d ciclos (%0d us)", HEX, ciclos, ciclos / 25);
    $display("LEDs = %b, display = %h", leds, display);
    $display("");

    revisar(ciclos <= 200000, "el programa termina");
    revisar(leds == 4'b1111, "LEDs = 1111 (ninguna prueba fallo)");
    revisar(display == 8'h10, "display = 10: las 16 pruebas del procesador pasaron");
    if (leds == 4'b0101)
      $display("     -> fallo la prueba %0d de sw/prueba_cpu.s", display);

    // Mediciones guardadas por el programa en 0x7F0 y 0x7F4 (palabras
    // 508 y 509 de la RAM). Se leen por dentro solo para informarlas.
    bucle1 = dut.u_pochoco.u_ram.mem[508];
    bucle2 = dut.u_pochoco.u_ram.mem[509];
    $display("");
    $display("Medido por el programa con el contador de ciclos:");
    $display("  1000 vueltas de {addi; bnez}          = %0d ciclos -> %0d ciclos por vuelta",
             bucle1, bucle1 / 1000);
    $display("  1000 vueltas de {lw botones; addi; bnez} = %0d ciclos -> %0d ciclos por vuelta",
             bucle2, bucle2 / 1000);
    $display("  a 25 MHz, una vuelta del bucle que lee los botones dura %0d ns", (bucle2 / 1000) * 40);

    $display("");
    $display("Pruebas aprobadas: %0d/%0d", pasadas, total);
    if (pasadas == total) $display("RESULTADO: el SoC ejecuta correctamente el programa.");
    else                  $display("RESULTADO: hay pruebas que fallaron.");
    $finish;
  end

endmodule
