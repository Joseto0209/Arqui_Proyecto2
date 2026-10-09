// tb_game.v
// Testbench del juego completo: game_top con sw/game.s corriendo en el
// Espino, y un "jugador" simulado que aprieta botones (con rebote).
//
// Para no simular 3 segundos reales (75 millones de ciclos por ronda),
// el juego se ensambla con una decima de 2.500 ciclos en vez de
// 2.500.000: todo pasa 1000 veces mas rapido, pero el programa es
// exactamente el mismo. Solo cambia la constante, gracias a -D:
//
//   python asm/asm.py sw/game.s -o build/game_sim.hex -D CICLOS_DECIMA=2500
//   sim tb_game
//
// Como en la diapositiva 6 del curso, el testbench solo usa los puertos
// del top: aprieta i_Switch, lee o_LED y decodifica los pines de los
// displays.
//
// Lo que se verifica, en orden:
//   - al encender espera un boton, con 00 y los LEDs apagados
//   - cada ronda parte con los 4 LEDs al menos 3 s (30 decimas)
//   - el objetivo es un solo LED, y el tiempo mostrado es el correcto
//   - un boton equivocado muestra EE, apaga los LEDs y repite la ronda
//     sin perder las rondas correctas
//   - un tiempo de mas de 9,9 s se muestra como 99
//   - tras la decima ronda: su tiempo, y despues el promedio redondeado
//     con los LEDs alternando 1001 / 0110
//   - un boton en la pantalla final empieza una partida nueva

`timescale 1ns/1ps

module tb_game;

  parameter HEX = "build/game_sim.hex";
  parameter CD  = 2500;                     // CICLOS_DECIMA de la simulacion

  reg clk = 1'b0;
  always #20 clk = ~clk;                    // 25 MHz

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
  // Displays: pines activos en bajo -> digito
  // ---------------------------------------------------------------
  function [3:0] digito(input g, f, e, d, c, b, a);
    begin
      case (~{g, f, e, d, c, b, a})
        7'b0111111: digito = 4'h0;  7'b0000110: digito = 4'h1;
        7'b1011011: digito = 4'h2;  7'b1001111: digito = 4'h3;
        7'b1100110: digito = 4'h4;  7'b1101101: digito = 4'h5;
        7'b1111101: digito = 4'h6;  7'b0000111: digito = 4'h7;
        7'b1111111: digito = 4'h8;  7'b1101111: digito = 4'h9;
        7'b1110111: digito = 4'hA;  7'b1111100: digito = 4'hB;
        7'b0111001: digito = 4'hC;  7'b1011110: digito = 4'hD;
        7'b1111001: digito = 4'hE;  7'b1110001: digito = 4'hF;
        default:    digito = 4'hX;
      endcase
    end
  endfunction

  wire [7:0] display = {digito(s1g, s1f, s1e, s1d, s1c, s1b, s1a),
                        digito(s2g, s2f, s2e, s2d, s2c, s2b, s2a)};

  // Decimas (0..99) -> lo que deberia verse en el display: 23 -> 8'h23
  function [7:0] bcd(input integer d);
    reg [3:0] decenas, unidades;
    begin
      decenas  = d / 10;
      unidades = d % 10;
      bcd = {decenas, unidades};
    end
  endfunction

  // ---------------------------------------------------------------
  // Contador de ciclos y verificacion
  // ---------------------------------------------------------------
  integer ciclo = 0;
  always @(posedge clk) ciclo = ciclo + 1;

  integer pasadas = 0, total = 0;
  task revisar(input condicion, input [8*72-1:0] etiqueta);
    begin
      total = total + 1;
      if (condicion) begin pasadas = pasadas + 1; $display("PASS %0s", etiqueta); end
      else           $display("FAIL %0s  (ciclo %0d, LEDs %b, display %h)",
                              etiqueta, ciclo, leds, display);
    end
  endtask

  // ---------------------------------------------------------------
  // Monitor de la fase inicial: cada vez que los 4 LEDs se apagan,
  // revisa que hayan estado encendidos al menos 30 decimas.
  // ---------------------------------------------------------------
  integer inicio_fase = 0, fases = 0, fases_cortas = 0, fase_minima = 0;
  always @(leds) begin
    if (leds == 4'b1111)
      inicio_fase = ciclo;
    else if (inicio_fase != 0) begin
      fases = fases + 1;
      if (fase_minima == 0 || ciclo - inicio_fase < fase_minima)
        fase_minima = ciclo - inicio_fase;
      if (ciclo - inicio_fase < 30 * CD)
        fases_cortas = fases_cortas + 1;
      inicio_fase = 0;
    end
  end

  // ---------------------------------------------------------------
  // El jugador
  // ---------------------------------------------------------------
  // Aprieta con rebote: el contacto se abre y cierra 4 veces antes de
  // quedar firme, como un pulsador real.
  reg [3:0] presionado = 4'b0000;

  task apretar(input [3:0] b);
    integer k;
    begin
      presionado = b;
      for (k = 0; k < 4; k = k + 1) begin
        botones = b;       repeat (30) @(posedge clk);
        botones = 4'b0000; repeat (30) @(posedge clk);
      end
      botones = b;
    end
  endtask

  // Suelta tambien con rebote
  task soltar;
    integer k;
    begin
      for (k = 0; k < 3; k = k + 1) begin
        botones = 4'b0000;   repeat (25) @(posedge clk);
        botones = presionado; repeat (25) @(posedge clk);
      end
      botones = 4'b0000;
    end
  endtask

  // Espera a que se encienda un solo LED; devuelve cual y cuando
  reg [3:0] objetivo;
  integer   t_objetivo;
  task esperar_objetivo;
    begin
      wait (leds == 4'b0001 || leds == 4'b0010 || leds == 4'b0100 || leds == 4'b1000);
      objetivo   = leds;
      t_objetivo = ciclo;
    end
  endtask

  // Espera hasta que el display muestre "valor" (con limite)
  task esperar_display(input [7:0] valor, input integer limite);
    integer k;
    begin
      k = 0;
      while (display !== valor && k < limite) begin
        @(posedge clk); k = k + 1;
      end
    end
  endtask

  // Tiempos de reaccion del jugador, en decimas. La ronda 5 tarda 12 s
  // (debe verse 99) y la 7 menos de una decima (debe verse 00).
  integer reaccion [0:9];
  integer mostrado, suma = 0, r, k, distintos;
  reg [3:0] equivocado;
  reg [3:0] vistos = 4'b0000;
  integer partida1 [0:15], partida2 [0:3];
  integer objetivos = 0;

  function integer indice(input [3:0] led);
    indice = led[0] ? 0 : led[1] ? 1 : led[2] ? 2 : 3;
  endfunction

  initial begin
    reaccion[0] = 3;   reaccion[1] = 7;  reaccion[2] = 12; reaccion[3] = 5;
    reaccion[4] = 120; reaccion[5] = 9;  reaccion[6] = 0;  reaccion[7] = 15;
    reaccion[8] = 6;   reaccion[9] = 9;

    // Solo las senales del testbench: la simulacion es larga
    $dumpfile("build/tb_game.vcd");
    $dumpvars(1, tb_game);

    // --- Al encender: espera el boton de inicio ---------------------
    repeat (40 * CD) @(posedge clk);
    revisar(leds == 4'b0000 && display == 8'h00,
            "al encender espera un boton con 00 y los LEDs apagados");

    apretar(4'b0001);
    repeat (CD) @(posedge clk);
    soltar;

    // --- Diez rondas correctas, con un error en la tercera ----------
    for (r = 0; r < 10; r = r + 1) begin
      esperar_objetivo;
      vistos = vistos | objetivo;
      partida1[objetivos] = indice(objetivo);
      objetivos = objetivos + 1;

      if (r == 2) begin
        // Boton equivocado: el siguiente al del LED objetivo
        equivocado = {objetivo[2:0], objetivo[3]};
        repeat (2 * CD) @(posedge clk);
        apretar(equivocado);
        esperar_display(8'hEE, 5000);
        revisar(display == 8'hEE && leds == 4'b0000,
                "boton equivocado: EE y LEDs apagados");
        soltar;
        wait (leds == 4'b1111);
        revisar(display == 8'hEE, "tras el error se repite la ronda (4 LEDs otra vez)");
        esperar_objetivo;
        vistos = vistos | objetivo;
        partida1[objetivos] = indice(objetivo);
        objetivos = objetivos + 1;
      end

      // Aprieta el boton correcto a mitad de la decima esperada
      repeat (reaccion[r] * CD + CD / 2) @(posedge clk);
      apretar(objetivo);
      mostrado = (reaccion[r] > 99) ? 99 : reaccion[r];
      esperar_display(bcd(mostrado), 5000);
      revisar(display == bcd(mostrado),
              reaccion[r] > 99 ? "ronda de 12 s: el display se queda en 99"
                               : "ronda correcta: el display muestra el tiempo en decimas");
      $display("     ronda %0d: LED %b, tiempo %0d decimas, display %h", r + 1, objetivo,
               reaccion[r], display);
      suma = suma + mostrado;
      soltar;

      if (r < 9) begin
        wait (leds == 4'b1111);
        revisar(display == bcd(mostrado), "el tiempo sigue visible durante la fase de 3 s");
      end
    end

    // --- Fin de la partida -------------------------------------------
    repeat (10 * CD) @(posedge clk);
    revisar(display == bcd(reaccion[9]) && leds == 4'b0000,
            "tras la ronda 10 se ve su tiempo con los LEDs apagados");

    wait (leds == 4'b1001);
    $display("     suma de las 10 rondas = %0d decimas, promedio = %0d / 10 = %0d,%0d -> %0d",
             suma, suma, suma / 10, suma % 10, (suma + 5) / 10);
    revisar(display == bcd((suma + 5) / 10),
            "promedio redondeado: 165 / 10 = 16,5 -> 17");
    wait (leds == 4'b0110);
    revisar(display == bcd((suma + 5) / 10), "pantalla final: LEDs alternan 1001 / 0110");

    revisar(fases == 11 && fases_cortas == 0,
            "las 11 fases iniciales duraron al menos 3 s (30 decimas)");
    $display("     fase inicial mas corta: %0d ciclos = %0d,%0d decimas",
             fase_minima, fase_minima / CD, (fase_minima % CD) * 10 / CD);

    distintos = vistos[0] + vistos[1] + vistos[2] + vistos[3];
    revisar(distintos >= 3, "el LED objetivo varia (al menos 3 LEDs distintos en 11 rondas)");
    $write("     LED objetivo en cada ronda de la partida 1:");
    for (k = 0; k < objetivos; k = k + 1) $write(" %0d", partida1[k]);
    $display("");

    // --- Partida nueva ------------------------------------------------
    apretar(4'b0010);
    repeat (CD) @(posedge clk);
    soltar;
    wait (leds == 4'b1111);
    revisar(display == 8'h00, "un boton en la pantalla final empieza otra partida (00)");
    for (k = 0; k < 4; k = k + 1) begin
      esperar_objetivo;
      partida2[k] = indice(objetivo);
      repeat (4 * CD) @(posedge clk);
      apretar(objetivo);
      repeat (CD) @(posedge clk);
      soltar;
    end
    $write("     LED objetivo en las primeras 4 rondas de la partida 2:");
    for (k = 0; k < 4; k = k + 1) $write(" %0d", partida2[k]);
    $display("");

    $display("");
    $display("Simulados %0d ciclos (%0d,%0d s de juego real)", ciclo, ciclo / 25000, (ciclo % 25000) / 2500);
    $display("Pruebas aprobadas: %0d/%0d", pasadas, total);
    if (pasadas == total) $display("RESULTADO: el juego cumple todos los requisitos simulados.");
    else                  $display("RESULTADO: hay pruebas que fallaron.");
    $finish;
  end

  // Limite de seguridad: si algo se cuelga, la simulacion termina igual
  initial begin
    #(64'd40 * 64'd5000000);
    $display("FAIL la simulacion no termino a tiempo (LEDs %b, display %h)", leds, display);
    $display("Pruebas aprobadas: %0d/%0d", pasadas, total + 1);
    $finish;
  end

endmodule
