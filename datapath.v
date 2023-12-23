module datapath(mdata, sximm8, PC, sximm5, C, readnum, writenum, 
				write, loada, loadb, loadc, asel, bsel, 
				vsel, shift, ALUop, clk, Z, V, N);

  input [15:0] mdata, PC, sximm5, sximm8; 
  input clk, write, loada, loadb, asel, bsel, loadc;
  input [2:0] readnum, writenum;
  input [1:0] shift, ALUop, vsel;

  output [15:0] C;
  output Z, N, V;
  
  
  wire [15:0] data_in, data_out, Apipe, Bpipe, sout, Ain, Bin, aout ;
  wire ALUZ, ALUV, ALUN ;

  //Instantiates MUX to select whether datapath_in or datapath_out will be the input
  //to the register
  Mux4 choose_data(mdata, sximm8, PC, C, vsel, data_in) ;
  
  //Instantiates the file register, its input is data_in, its output is data_out
  regfile REGFILE(data_in, writenum, write, readnum, clk, data_out) ;
  
  //Instantiates a load enabled register each for the values
  //that will need to be stored in registers A and Bin
  //This storage allows for two different values to be set
  //sequentially and then be inputs into the combinational ALU operation
  vPipeline #(16) vDFFA(clk, data_out, Apipe, loada) ;
  vPipeline #(16) vDFFB(clk, data_out, Bpipe, loadb) ;
  
  //Instantiates shifter after the loaded register B outputs Bpipe
  shifter Bshift(Bpipe, shift, sout) ;
  
  //Instantiates MUX to select whether the inputs Apipe and sout should be modified
  //before being passed into the ALU
  Multiplexerdata #(16,1) chooseB(sout, sximm5, bsel, Bin) ;
  Multiplexerdata #(16,1) chooseA(Apipe, 16'b0, asel, Ain) ;
  
  //Instantiates ALU that will perform bitwise operations on Ain and Bin
  ALU aluAB(Ain, Bin, ALUop, aout, ALUN, ALUV, ALUZ) ;
  
  //Instantiates load enabled registers to store the value of 
  //datapath_out and Z, V and N and set it as output when the load is high
  //VDDFstatus will only set the inputs to the output if ALUop is equal to 2'b01 (CMP)
  vDFFstatus #(3) status(clk, ALUop, {ALUZ, ALUV, ALUN}, {Z, V, N}) ; 
  vPipeline #(16) dataC(clk, aout, C, loadc) ;

endmodule
  
//This will select what to output between two inputs
//If the selector is high, then in1 will be the output, otherwise
//in0 is the output
module Multiplexerdata(in0, in1, selector, out);
	parameter k, n;
	input [k-1:0] in0, in1;
	input [n-1:0] selector;
	output[k-1:0] out;
	reg [k-1:0] temp_out;

	always@(selector or in0 or in1)begin

	case (selector) 

	1'b0: temp_out = in0;
	1'b1: temp_out = in1;


	default: temp_out = {16{1'bx}};

	endcase

	end

	assign out = temp_out ;

endmodule

module Mux4(in0, in1, in2, in3, selector, out);
	input [15:0] in0, in1, in2, in3;
	input [1:0] selector;
	output[15:0] out;
	reg [15:0] temp_out;

	always@(selector or in0 or in1 or in2 or in3)begin

	case (selector) 

	2'b00: temp_out = in0;
	2'b01: temp_out = in1;
	2'b10: temp_out = in2;
	2'b11: temp_out = in3;

	default: temp_out = {16{1'bx}};

	endcase

	end

	assign out = temp_out ;

endmodule
//Load enabled register that will hold its current value
//its output value may be altered when the load is high
module vPipeline(clk, in, out, load);
  parameter n;
  input clk;
  input [n-1:0] in;
  input load ;
  output [n-1:0] out;
  reg [n-1:0] temp_out;

//Will copy in to temp_out if the load is equal to 1, 
//otherwise output does not change
  always @(posedge clk)begin
	temp_out <= (load == 1'b1)? in : out ;
  end
  assign out = temp_out ;
endmodule

