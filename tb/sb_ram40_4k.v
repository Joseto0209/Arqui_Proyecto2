// sb_ram40_4k.v
// Modelo de simulacion del bloque de RAM SB_RAM40_4K de la iCE40.
// SOLO PARA SIMULACION: nunca se le pasa a Yosys, que usa el bloque
// real de la FPGA.
//
// El register file del Espino (espino_register_file.v) instancia este
// bloque directamente. iverilog no lo conoce, asi que sin este modelo
// el SoC no compila en simulacion. Se implementa solo lo que usa el
// Espino, con el comportamiento documentado por Lattice:
//
//   READ_MODE = WRITE_MODE = 0  ->  256 palabras de 16 bits
//   Lectura sincrona: RDATA se actualiza en el flanco de RCLK.
//   Escritura sincrona en el flanco de WCLK. Un bit de MASK en 1
//   protege ese bit (no se escribe).
//   Si se lee y escribe la misma direccion en el mismo flanco, la
//   lectura entrega el valor anterior.
//   INIT_0 .. INIT_F: contenido inicial, 16 palabras por parametro.
//
// Se verifico contra el modelo oficial de Yosys (share/yosys/ice40/
// cells_sim.v): ambos dan resultados identicos en tb_soc.

module SB_RAM40_4K #(
  parameter READ_MODE  = 0,
  parameter WRITE_MODE = 0,
  parameter [255:0] INIT_0 = 256'h0, INIT_1 = 256'h0, INIT_2 = 256'h0, INIT_3 = 256'h0,
  parameter [255:0] INIT_4 = 256'h0, INIT_5 = 256'h0, INIT_6 = 256'h0, INIT_7 = 256'h0,
  parameter [255:0] INIT_8 = 256'h0, INIT_9 = 256'h0, INIT_A = 256'h0, INIT_B = 256'h0,
  parameter [255:0] INIT_C = 256'h0, INIT_D = 256'h0, INIT_E = 256'h0, INIT_F = 256'h0
) (
  output reg  [15:0] RDATA,
  input  wire        RCLK, RCLKE, RE,
  input  wire [10:0] RADDR,
  input  wire        WCLK, WCLKE, WE,
  input  wire [10:0] WADDR,
  input  wire [15:0] MASK,
  input  wire [15:0] WDATA
);

  reg [15:0] mem [0:255];
  integer i, k;

  initial begin
    for (i = 0; i < 16; i = i + 1) begin
      mem[  0 + i] = INIT_0[16*i +: 16];  mem[ 16 + i] = INIT_1[16*i +: 16];
      mem[ 32 + i] = INIT_2[16*i +: 16];  mem[ 48 + i] = INIT_3[16*i +: 16];
      mem[ 64 + i] = INIT_4[16*i +: 16];  mem[ 80 + i] = INIT_5[16*i +: 16];
      mem[ 96 + i] = INIT_6[16*i +: 16];  mem[112 + i] = INIT_7[16*i +: 16];
      mem[128 + i] = INIT_8[16*i +: 16];  mem[144 + i] = INIT_9[16*i +: 16];
      mem[160 + i] = INIT_A[16*i +: 16];  mem[176 + i] = INIT_B[16*i +: 16];
      mem[192 + i] = INIT_C[16*i +: 16];  mem[208 + i] = INIT_D[16*i +: 16];
      mem[224 + i] = INIT_E[16*i +: 16];  mem[240 + i] = INIT_F[16*i +: 16];
    end
    RDATA = 16'h0;
  end

  // Lectura: con asignacion no bloqueante entrega el valor anterior
  // aunque la misma direccion se escriba en el mismo flanco.
  always @(posedge RCLK)
    if (RCLKE && RE) RDATA <= mem[RADDR[7:0]];

  always @(posedge WCLK)
    if (WCLKE && WE)
      for (k = 0; k < 16; k = k + 1)
        if (!MASK[k]) mem[WADDR[7:0]][k] <= WDATA[k];

endmodule
