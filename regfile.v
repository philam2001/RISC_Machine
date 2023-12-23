//Define macros that indicate the binary position of each register

`define Zeror 8'b00000001
`define Oner 8'b00000010
`define Twor 8'b00000100
`define Threer 8'b00001000
`define Fourr 8'b00010000
`define Fiver 8'b00100000
`define Sixr 8'b01000000
`define Sevenr 8'b10000000

module regfile(data_in, writenum, write, readnum, clk, data_out);
	input [15:0] data_in;
	input [2:0] writenum, readnum;
	input write, clk ;
	output [15:0] data_out ; 
	reg [15:0] R0, R1, R2, R3, R4, R5, R6, R7 ;
	wire [7:0] onehotw, onehotr, writeload ; 
	
	//Instantiates a decoder each to convert both the 3 bit wide
	//writenum and readnum binary inputs to an 8-bit one-hot code
	decoder #(3,8) writing(writenum, onehotw);
	decoder #(3,8) reading(readnum, onehotr);
	
	//This MUX selects what register to read from and then copies 
	//that registers value to data_out
	Multiplexer #(16,8) out(R0, R1, R2, R3, R4, R5, R6, R7, onehotr, data_out);
 
	//writeload will only have at most 1 bit set to 1, which indicates
	//which register to write to. If write is zero, then writeload is zero
	//and no register will be written to
	assign writeload = onehotw&{8{write}} ;
	
	always @(posedge clk) begin
		
		case(writeload)
		//Depending on writeload, one register will be set to data_in
		`Zeror: R0 = data_in;
		`Oner: R1 = data_in;
		`Twor: R2 = data_in;
		`Threer: R3 = data_in;
		`Fourr: R4 = data_in;
		`Fiver: R5 = data_in;
		`Sixr: R6 = data_in;
		`Sevenr: R7 = data_in;
		
		//Mundane default statement to avoid latches
		default: R0 = R0;
		endcase 
	end
	
	
endmodule

//Decoder module:

module decoder(in, ohot);
	parameter n, m ;
	
	input [n-1:0] in;
	output [m-1:0] ohot;
	
	assign ohot = 1<<in ; 
endmodule

module Multiplexer(a0, a1, a2, a3, a4, a5, a6, a7, selector, out);
	parameter k, n;
	input [k-1:0] a0, a1, a2, a3, a4, a5, a6, a7;
	input [n-1:0] selector;
	output[k-1:0] out;
	reg [k-1:0] temp_out;
	
	//combinational operation that does not run on the clock, so it will be 
	//evaluated whenever the selector, that is onehotr, changes
	always@(selector or a0 or a1 or a2 or a3 or a4 or a5 or a6 or a7)begin
	
	case (selector) 
	//one register will be read from depending on selector
	`Zeror: temp_out = a0;
	`Oner: temp_out = a1;
	`Twor: temp_out = a2;
	`Threer: temp_out = a3;
	`Fourr: temp_out = a4;
	`Fiver: temp_out = a5;
	`Sixr: temp_out = a6;
	`Sevenr: temp_out = a7;
	//otherwise set output to don't care
	default: temp_out = {16{1'bx}};
	
	endcase
	
	end
	
	assign out = temp_out ;

endmodule
	
	
	
	
	
	
	
	
	
	
