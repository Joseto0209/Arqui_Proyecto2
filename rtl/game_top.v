// game_top.v
// Proyecto 2 - Juego de reflejos sobre Pochoco SoC
// ICC3302 Arquitectura de Computadores, Universidad de los Andes, 2026-2
//
// Modulo superior que se sintetiza y graba en la FPGA. No agrega
// logica propia: instancia el Pochoco SoC, elige la imagen de memoria
// del juego (sw/game.hex) y conecta los pines de la Go Board.
//
//   Reloj        i_Clk                25 MHz
//   LEDs         o_LED[3:0]           LED i  = bit i de 0x8000_0004
//   Botones      i_Switch[3:0]        boton i = bit i de 0x8000_0008
//   Displays     o_Segment1_*, 2_*    byte escrito en 0x8000_0000
//   SPI          i_SPI_*, o_SPI_MISO  conectado al PMOD, sin uso
//
// El nombre de cada puerto coincide con goboard.pcf, que es lo que
// usa nextpnr para asignar cada senal a su pin fisico.
//
// MemFile es un parametro para poder cambiar el programa sin editar
// este archivo (por ejemplo, con chparam en Yosys o en un testbench).
// La ruta es relativa a la carpeta desde donde se corre la
// herramienta, que siempre es la raiz del repositorio.

module game_top #(
  parameter MemFile = "sw/game.hex"
) (
  input  wire       i_Clk,

  output wire [3:0] o_LED,
  input  wire [3:0] i_Switch,

  output wire       o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D,
  output wire       o_Segment1_E, o_Segment1_F, o_Segment1_G,
  output wire       o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D,
  output wire       o_Segment2_E, o_Segment2_F, o_Segment2_G,

  input  wire       i_SPI_SCLK,
  input  wire       i_SPI_MOSI,
  input  wire       i_SPI_CS_n,
  output wire       o_SPI_MISO
);

  pochoco_soc #(
    .MemFile (MemFile)
  ) u_pochoco (
    .i_Clk        (i_Clk),

    .o_LED        (o_LED),
    .i_Switch     (i_Switch),

    .o_Segment1_A (o_Segment1_A),
    .o_Segment1_B (o_Segment1_B),
    .o_Segment1_C (o_Segment1_C),
    .o_Segment1_D (o_Segment1_D),
    .o_Segment1_E (o_Segment1_E),
    .o_Segment1_F (o_Segment1_F),
    .o_Segment1_G (o_Segment1_G),

    .o_Segment2_A (o_Segment2_A),
    .o_Segment2_B (o_Segment2_B),
    .o_Segment2_C (o_Segment2_C),
    .o_Segment2_D (o_Segment2_D),
    .o_Segment2_E (o_Segment2_E),
    .o_Segment2_F (o_Segment2_F),
    .o_Segment2_G (o_Segment2_G),

    .i_SPI_SCLK   (i_SPI_SCLK),
    .i_SPI_MOSI   (i_SPI_MOSI),
    .i_SPI_CS_n   (i_SPI_CS_n),
    .o_SPI_MISO   (o_SPI_MISO)
  );

endmodule
