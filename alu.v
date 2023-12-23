module ALU(Ain, Bin, ALUop, out, N, V, Z);
    input [15:0] Ain, Bin;
    input [1:0] ALUop;
    output [15:0] out;
    output Z, N, V;
    
    reg [15:0] val;
    
   //Checks to see what input ALUop is and perform the corresponding operation
   always @(Ain or Bin or ALUop) begin
        case(ALUop)
          2'b00: val = Ain + Bin;
          2'b01: val = Ain - Bin;
          2'b10: val = Ain & Bin;
          2'b11: val = ~Bin;
    //Set a default so that there are no inferred latches   
        default: val = 16'bxxxxxxxxxxxxxxxx;
        endcase
		
    end
    //assigns the value of val to the output out
    assign out = val;
    //assigns Z the value of 1 if the value of val is 16'b0
    assign Z = (val == 16'b0) ? 1'b1 : 1'b0;
    assign N = val[15] ;
    
    DetectOverflow #(16) OVF(Ain, Bin, ALUop, V);

endmodule


//Half Adder that will be instantiated inside the Overflow Detector
module HalfAdder (a, b, cin, cout, s);
	parameter n;
	input [n-1:0] a, b;
	input cin;
	output [n-1:0] s;
	output cout;
	
	wire [n-1:0] p = a ^ b;
	wire [n-1:0] g = a & b;
	wire [n:0] 	 c = {g|(p & c[n-1:0]), cin};
	wire [n-1:0] s = p ^ c[n-1:0];
	wire 	  cout = c[n];
endmodule

//Detects Overflow, based off of Detector in lecture slides
module DetectOverflow (a, b, s, ovf);
	parameter n;
	input [n-1:0] a, b;
	input [1:0] s;
	output ovf;
	wire [n-1:0] sum;
	wire c1, c2, subtract ;
	wire ovf = c1 ^ c2 ;
	
	assign subtract = (s == 2'b01) ? 1'b1 : 1'b0;
	
	HalfAdder #(n-1) nonsign(a[n-2:0], b[n-2:0]^{n-1{subtract}}, subtract, c1, sum[n-2:0]);
	
	HalfAdder #(1) sign(a[n-1], b[n-1]^subtract, c1, c2, sum[n-1]);
	

endmodule

//updates the N,V and Z flags when load is equal to 01, the ALU CMP instruction
module vDFFstatus (clk, load, D, Q);
  parameter n;
  input clk;
  input [n-1:0] D;
  input [1:0] load;
  output [n-1:0] Q;
  reg [n-1:0] Q;

  always @(posedge clk)
    case (load)
	2'b01: Q <= D;
	default: Q<=Q;
	endcase
endmodule
