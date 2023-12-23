module shifter(in, shift, sout);
	input [15:0] in;
	input [1:0] shift;
	output [15:0] sout;
	
	reg [15:0] outval;

	always @* begin
		 case(shift)
		  //output remains unchanged
		  2'b00: outval = in;
		  //when input of shift is 2'b01, shifts value to the left and assign 0 to the outval[0]
		  2'b01: outval = {in[14:0], 1'b0};
		  //when input of shift is 2'b10, shifts value to the right and assign 0 to the outval[15]
		  2'b10: outval = {1'b0, in[15:1]};
		  //when input of shift is 2'b11, shifts value to the right and assign in[15] to the outval[15]
		  2'b11: outval = {in[15], in[15:1]};
		  //default undefined value
		  default: outval = {16{1'bx}};
		 endcase
   	  end
   //assigns reg outval to the output sout
   assign sout = outval;
endmodule
