`define RST 4'b0000
`define Decode 4'b0001
`define WriteImm 4'b0010
`define MoveSH 4'b0011
`define GetA 4'b0100
`define GetB 4'b0101
`define ALU 4'b0110
`define WriteReg 4'b0111
`define IF1 4'b1000
`define PCWAIT 4'b1001
`define BWait 4'b1010
`define STRWrite 4'b1011
`define STRAddy 4'b1100
`define HALT 4'b1101
`define LDRwait 4'b1110
`define RST2 4'b1111
`define ST 4
`define MWRITE 2'b10
`define MREAD 2'b01
`define MNONE 2'b00
`define B 3'b000
`define BEQ 3'b001
`define BNE 3'b010
`define BLT 3'b011
`define BLE 3'b100

module cpu(clk, reset, in, out, N ,V, Z, mem_addr, mem_cmd, HALTLED);
	input clk, reset;
	input [15:0] in;
	output [15:0] out;
	output [8:0] mem_addr;
	output [1:0] mem_cmd;
	output N, V, Z, HALTLED;
	
	wire [15:0] in_decoder, sximm8, sximm5;
	wire [2:0] writenum, readnum, opcode, condition ;
	wire [1:0] ALUop, op, shift, nsel, vsel;
	wire [8:0] PC, next_pc, data_address;
	wire asel, bsel, loada, loadb, loadc, write, reset_pc, addr_sel, load_addr, load_pc, load_ir;
	
	//drives the wire that feeds into the MUX that returns PC depending on the condition  of Z, N, V or return 9'b0 if it's reset_pc = 1;
	PC_MUX choose_next_pc(opcode, op, condition, sximm8, N, V, Z, PC, next_pc, reset_pc, out);


	//2 input mux that selects between the program counter or address output by datapath to drive to memory address
    assign mem_addr = addr_sel ? PC : data_address ; 
	//Instantiate register to store and pass ARM instruction to decoder
	LoadRegister #(16) LOAD(clk, in, in_decoder, load_ir);

	//stores the current PC
	LoadRegister #(9) PCCount(clk, next_pc, PC, load_pc);

	//Stores the address output by datapath
	LoadRegister #(9) DataAddress(clk, out[8:0], data_address, load_addr);
	
	//Decodes the 16-bit instruction and passes the settings to the datapath module
	//Take nsel as input as well 
	InstructionDecoder FORDP(in_decoder, nsel, opcode, op, 
						ALUop, sximm5, sximm8, shift, readnum, writenum, condition); 
	
	//FSM that controls the transition from state to state, sets controlling inputs of the datapath module 
	ControllerFSM FSM(clk, reset, opcode, op, ALUop, nsel, write, loada, loadb, loadc, asel, bsel, vsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd, HALTLED); 
	
	//datapath module that writes/reads to/from register file, performs ALU operations and outputs N,V,Z flags (w) and the result of the 	//ALU operation, unless it is a CMP operation
	datapath DP(in, sximm8, {7'b0, PC}+1'b1, sximm5, out, readnum, writenum, 
				write, loada, loadb, loadc, asel, bsel, vsel, 
				shift, ALUop, clk, Z, V, N);
				
endmodule

//note: nsel selects Rn for 2'b00, Rd for 2'b01, Rm for 2'b10
//vsel outputs sximm8 when selector is 2'b01; selects C when selector is 2'b11;
module InstructionDecoder (in, nsel, opcode, op, ALUop, 
						   sximm5, sximm8, shift, readnum, writenum, condition);
	input [15:0] in;
	input [1:0] nsel;
	output [2:0] opcode, readnum, writenum, condition;
	output [1:0] shift, ALUop, op;
	output [15:0] sximm5, sximm8 ; 
	
	wire [2:0] Rn, Rd, Rm, MUX_out;
	
	//assigns the corresponding bits to each output
	assign opcode = in[15:13];
	assign op = in[12:11];
	assign Rn = in[10:8];
	assign Rd = in[7:5];
	assign Rm = in[2:0];
	assign condition = in[10:8];
	//Does not shift if the operation is STR or LDR
	assign shift = ((in[15:13] == 3'b010) || (in[15:13] == 3'b011) || (in[15:13] == 3'b100))? 2'b00 : in[4:3];
	assign ALUop = (opcode == 3'b010) ? 2'b00  : in[12:11] ;
	//sign extends one's if the MSB is equal to 1, sign extends zeros otherwise
	assign sximm5 = in[4] ? {{11{1'b1}}, in[4:0]} : {{11{1'b0}},in[4:0]};
	assign sximm8 = in[7] ? {{8{1'b1}}, in[7:0]} : {{8{1'b0}},in[7:0]} ;
	assign readnum = MUX_out;
	assign writenum = MUX_out;
	
	//Instantiates binary select multiplexer to take either Rn, Rd or Rm as the input to write/readnum
	Mux3 NSEL(Rn, Rd, Rm, nsel, MUX_out);
	
endmodule
	
module ControllerFSM(clk, reset, opcode, op, ALUop, nsel, write, loada, loadb, loadc, asel, bsel, vsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd, HALTLED);
	input clk, reset;
	input [2:0] opcode; 
	input [1:0] op, ALUop;

	output reg write, loada, loadb, loadc, asel, bsel, addr_sel, reset_pc, load_pc, load_addr, load_ir;
	output reg [1:0] vsel, nsel, mem_cmd;
	output HALTLED;


	reg [3:0] next_state;
	wire [3:0] present_state, reset_state; 
	//assigns 1 to w whenever the present state i
	assign reset_state = reset ? `RST : next_state ;
	assign HALTLED = (present_state == `HALT) ? 1'b1 : 1'b0;

	//all loads, 1 bit, 
	//Instantiates VDFF register in order to update the present state on rising edge of clk
	vDFFcpu #(`ST) STATE(clk, reset_state, present_state);

	//use wildcard so that it is evaluated whenever any input changes
	always @ (*) begin
		//use casex for cases that have more than one corresponding setting
		casex({opcode, op, present_state})

			//Initialize new instruction stage

			//Continues to IF1 in the RST state, sets reset_pc and load_pc to 1 in order to set the PC to zero
			{{5{1'bx}}, `RST}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {
				`RST2, 12'b0,1'b1, 1'b0, 1'b1, `MNONE};
				
			//set address select to 1; address select will be set to 1 in nearly every state, with the states of the STR and LDR instructions being the exception
			{{5{1'bx}}, `RST2}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {
				`IF1, 10'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, `MREAD};

			//Goes from IF1 to Decode; sets addr_sel to 1 in order to pass the address to memory for reading, sets MREAD to 1 as well				 
			{{5{1'bx}}, `IF1}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {
				`Decode, 10'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, `MREAD};

			//Goes from PCWAIT to IF1 ; sets addr_sel to 1 in order to pass the address to memory for reading, sets mem_cmd to MREAD as well				 
			{3'b001, 2'b00, `PCWAIT}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {
				`IF1, 10'b0, 1'b1, 1'b0, 1'b0, 2'b0, `MREAD};
				
			//For the branch instructions 
			{3'b010, 2'bxx, `PCWAIT}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {
				`IF1, 10'b0, 1'b1, 1'b0, 1'b0, 2'b0, `MREAD};
				
			//{3'b111, {2{1'bx}}, `PCWAIT}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {
			//	`HALT, 10'b0, 1'b0, 1'b0, 1'b0, 2'b0, `MNONE};
				
			//Loop back to PCWAIT, set all outputs to zeros
			{3'b111, {2{1'bx}}, `HALT} : {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`HALT, 15'b0, `MNONE};


			// //Special branches for BL and BLX that skip the loadpc state at first, loadpc will be set to 1 later
			// {5'b01010, `IF2}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {
			// 	`Decode, 10'b0, 1'b1, 2'b0, 1'b1, 1'b0, `MREAD};
			
			// //Special branch for BLX to skip loadPC as we need to use previous pc value to be placed in the register, loadpc will be set to 1 later
			// {5'b01011, `IF2}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {
			// 	`Decode, 10'b0, 1'b1, 2'b0, 1'b1, 1'b0, `MREAD};

			//Goes from LoadPc tp the decode state; sets load_pc to 1 in order to update PC for the next instruction
			// {{5{1'bx}}, `LoadPC}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {
			// 	`Decode, 12'b0, 1'b1, 2'b0, `MNONE};
			

			//Decode instruction and move to first state

			//Branch instructions come first because there are other cases below that have all don't cares
			//Todo: create condition in decoder, add the branch states, 
			

			//note: vsel 2'b00 = mdata; 2'b01 = sximm8, 2'b10 = PC, 2'b11 = C
			//goes to GetB (Rm) in order to move it to the specified register


			//Loop back to PCWAIT, loads pc to the next one
			{3'b001, 2'b00, `Decode} : {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {`PCWAIT, 10'b0, 1'b0, 1'b0, 1'b1, 2'b0, `MNONE};
			
			//MOVSH
			{3'b110, 2'b00, `Decode} : {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {`GetB, 10'b0, 1'b0, 1'b0, 1'b1, 2'b0, `MNONE};

			//When opcode is 101 and ALUop is 11, we don't go to get A and instead just get B
			{3'b101, 2'b11, `Decode} : {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {`GetB, 10'b0, 1'b0, 1'b0, 1'b1, 2'b0, `MNONE};


			//Bx, don't load PC here yet
			{3'b010, 2'b00, `Decode} : {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {`GetB, 10'b0, 1'b0, 1'b0, 1'b0, 2'b0, `MNONE};
 

			//Go to write immediate when opcode is 110 and op is 10
			{3'b110, 2'b10, `Decode} : {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {`WriteImm, 10'b0, 1'b0, 1'b0, 1'b1, 2'b0, `MNONE};

			//BL, During branch instructions, we don't set load_pc to 1 in order to first store PC+1 into R7, next_pc is currently PC+1+sximm8
			{5'b01011, `Decode} : {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {`WriteImm, 10'b0, 1'b0, 1'b0, 1'b0, 2'b0, `MNONE};


			//CLX, During branch instructions, we don't set load_pc to 1 in order to first store PC+1 into R7, next_pc is currently PC+1+sximm8
			{5'b01010, `Decode} : {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {`WriteImm, 10'b0, 1'b0, 1'b0, 1'b0, 2'b0, `MNONE};


			//Decode -> Halt
			//Move to halt state
			{3'b111, {2{1'bx}}, `Decode} : {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`HALT, 12'b0, 1'b1, 2'b0, `MNONE};


			//In any other case, we move to GetA
			{{5{1'bx}}, `Decode} : {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = {`GetA, 10'b0, 1'b0, 1'b0, 1'b1, 2'b0, `MNONE};
			
			
			
			//Whenever in GetA, we set loada to 1 to move the data to Pipeline Register A, then move to GetB
			{{5{1'bx}}, `GetA}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`GetB, 1'b0, 1'b1, 2'b0, 2'b00, 2'b00, 1'b0, 6'b0, `MNONE};
			
			
			
			//GetB -> ALU if LDR: in this special case, we read the B value from Rd (nsel=2'b01)
			{3'b011, 2'b00, `GetB}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`ALU, 2'b0, 1'b1, 1'b0, 2'b00, 2'b01, 1'b0, 1'b0, 5'b0, `MNONE};

			//GetB -> ALU if STR: in this special case, we read the B value from Rd (nsel=2'b01)
			{3'b100, 2'b00, `GetB}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`ALU, 2'b0, 1'b1, 1'b0, 2'b00, 2'b01, 1'b0, 1'b0, 5'b0, `MNONE};
			//Bx, GetB -> ALU
			{3'b010, 2'b00, `GetB}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`ALU, 2'b0, 1'b1, 1'b0, 2'b00, 2'b01, 1'b0, 1'b0, 5'b0, `MNONE};
			


			
			//ALU->STRAddy if LDR: We set bsel to 1 in order to pass the sign extended im5 value to Bin 
			{3'b011, 2'b00, `ALU}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`STRAddy, 3'b0, 1'b1, 5'b0, 1'b1, 1'b0, 1'b1, 3'b0,`MNONE};
			
			//BX, set loadc to 1, go to a Bwait state
			{3'b010, 2'b00, `ALU}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`BWait, 3'b0, 1'b1, 4'b0, 1'b1, 3'b0, 1'b0, 2'b0,`MNONE};
			
			//BX,Lets the datapath output update , then sets load pc to 1
			{3'b010, 2'b00, `BWait}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`PCWAIT, 3'b0, 1'b0, 4'b0, 1'b1, 3'b0, 1'b1, 2'b0,`MNONE};


			//ALU->STRAddy if STR: We set bsel to 1 in order to pass the sign extended im5 value to Bin 
			{3'b100, 2'b0, `ALU}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`STRAddy, 3'b0, 1'b1, 5'b0, 1'b1, 1'b0, 1'b1, 3'b0, `MNONE};

			//STRAddy -> LDRwait; set addr_sel to 1 in order to load the address;
			{3'b011, 2'b0, `STRAddy}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`LDRwait, 11'b0 , 1'b1, 3'b0, `MNONE};
			
			//LDRwait --> Writereg: Need an extra waiting state because multiple load enabled registers need to be update in sequential clock cycles
			// set the mem command to MREAD in order to read
			{3'b011, 2'b0, `LDRwait}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`WriteReg, 11'b0 , 1'b1, 3'b0, `MREAD};

			
			//STRAddy -> STRWrite if STR, set addr_sel to 1 in order to load the address; 
			{3'b100, 2'b0, `STRAddy}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} =
			{`STRWrite, 3'b0 , 1'b1, 4'b0, 1'b1, 2'b0, 1'b1, 3'b0, `MNONE};
			
			//STRWrite to IF1; we set mem command to MWRITE in order to write into memory
			{3'b100, 2'b0, `STRWrite}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} =
			{`LDRwait, 4'b0, 2'b0, 2'b10, 1'b1, 1'b0 , 5'b0, `MWRITE};
			
			{3'b100, 2'b0, `LDRwait}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} =
			{`IF1, 4'b0, 2'b0, 2'b00, 1'b0, 1'b0 , 1'b1, 4'b0, `MREAD};

 
			//BL, write PC+1 into R7
			{3'b010, 2'b11, `WriteImm}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`PCWAIT, 1'b1, 3'b0, 2'b10, 2'b00, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 2'b0, `MNONE};

			//BLX, Write PC+1 into R7 then continue to getB in order to set PC=Rd, we also set nsel to 00 to choose Rn as the register to  write to
			{3'b010, 2'b10, `WriteImm}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`GetB, 1'b1, 3'b0, 2'b10, 2'b00, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 2'b0, `MNONE};

			//Set loadb to 1
			{3'b010, 2'b10, `GetB}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`ALU, 2'b0, 1'b1, 1'b0, 2'b00, 2'b01, 1'b0, 1'b0, 1'b1, 4'b0, `MNONE};

			//Set loadc to 1, asel to 1 as well
			{3'b010, 2'b10, `ALU}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`BWait, 3'b0, 1'b1, 2'b00, 2'b00, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 2'b0, `MNONE};

			//Waits for datapath output to update, loads pc to set PC equal to Rd
			{3'b010, 2'b10, `BWait}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`PCWAIT, 3'b0, 1'b0, 2'b00, 2'b00, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 2'b0, `MNONE};


			//Go back to IF1 from write immediate
			{3'b110, 2'b10, `WriteImm}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`IF1, 1'b1, 3'b0, 2'b01, 2'b00, 1'b0, 1'b0, 1'b1, 4'b0, `MREAD};
			
			//Goes from GetB to MOVsh,  set loadb to 1 to move the data to Register B
			{3'b110, 2'b00, `GetB}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`MoveSH, 2'b0, 1'b1, 1'b0, 2'b00, 2'b10, 1'b0, 6'b0, `MNONE};
			
			
			//Goes from GetB to the ALU state, set loadb to 1 to move the data to Register B
			{3'b101, {2{1'bx}}, `GetB}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`ALU, 2'b0, 1'b1, 1'b0, 2'b0, 2'b10, 1'b0, 6'b0, `MNONE};		

	
			//ALU[CMP] --> IF1, so that no writing occurs
			{3'b101, 2'b01, `ALU}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`IF1, 3'b0, 1'b0, 4'b0, 1'b0, 1'b0, 1'b1, 4'b0, `MREAD};
		
			//ALU --> WriteReg state, set loadc to 1 to copy ALU's output to C Register
			{3'b101, {2{1'bx}}, `ALU}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`WriteReg, 3'b0, 1'b1, 11'b0, `MNONE};
			

			//since opcode is 110 and op is 00, we moved to a special ALU state (MoveSH) where asel is set to 1, set loadc to to write to C register
			{3'b110, 2'b00, `MoveSH}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`WriteReg, 3'b0, 1'b1, 4'b0, 1'b1, 6'b0, `MNONE};
			
			//WriteReg to IF1 if LDR (special case because mdata must be chosen as input
			{3'b011, {2{1'bx}}, `WriteReg}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`IF1, 1'b1, 3'b0, 2'b00, 2'b01, 2'b0, 1'b1, 4'b0, `MREAD};

			//WriteReg ->IF1, set write to 1 in order to write to register file, set vsel to 11 to select C, nsel to 01 to select Rd
			{{5{1'bx}}, `WriteReg}: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`IF1, 1'b1, 3'b0, 2'b11, 2'b01, 2'b0, 1'b1, 4'b0, `MREAD};
			
			
			//set all outputs to zero, go tF1 state
			default: {next_state, write, loada, loadb, loadc, vsel, nsel, asel, bsel, addr_sel, load_addr, load_pc, load_ir, reset_pc, mem_cmd} = 
			{`RST, 15'b0, `MNONE} ;
			
		endcase
	end
endmodule

//load enabled register that updates the instruction to the decoder on the rising edge of clk
module LoadRegister(clk, in, out, load);
  parameter n;
  input clk;
  input [n-1:0] in;
  input load ;
  output [n-1:0] out;
  reg [n-1:0] temp_out;

  always @(posedge clk)begin
	//assign in to temp_out when load is 1'b1
	temp_out <= (load == 1'b1)? in : out ;
  end
  assign out = temp_out ;
endmodule

//drives either Rn, Rd or Rm to output depending on nsel as selector
module Mux3(in0, in1, in2, selector, out);
	input [2:0] in0, in1, in2;
	input [1:0] selector;
	output[2:0] out;
	reg [2:0] temp_out;

	//all inputs inside sensitivity list
	always@(selector or in0 or in1 or in2)begin

	case (selector) 
	
	3'b00: temp_out = in0;
	3'b01: temp_out = in1;
	3'b10: temp_out = in2;

	default: temp_out = {3{1'bx}};

	endcase

	end

	assign out = temp_out ;

endmodule


//Flip Flop Register to update present_state on rising edge
module vDFFcpu(clk, D, Q);
  parameter n;
  input clk;
  input [n-1:0] D;
  output [n-1:0] Q;
  reg [n-1:0] Q;

  always @(posedge clk)
    Q <= D;
endmodule

module PC_MUX(opcode, op, cond, sximm8, N, V, Z, PC, next_pc, reset_pc, datapath_out);
input [2:0] opcode, cond;
input [1:0] op;
input [15:0] sximm8;
input N, V, Z, reset_pc;
input [8:0] PC;
input [15:0] datapath_out;
output reg [8:0] next_pc;

always @(*) begin
	casex({opcode, op, cond, reset_pc})
	
	{{8{1'bx}}, 1'b1}: next_pc = 9'b0;
	{3'b010, 2'bx0, 3'bxxx, 1'bx}: next_pc = datapath_out[8:0];
	{3'b010, 2'b11, 3'bxxx, 1'bx}: next_pc = PC + 1'b1 + sximm8[8:0];
	{3'b001, 2'b0, `B, 1'bx}: next_pc = PC + 1'b1 + sximm8[8:0]; 
	{3'b001, 2'b0, `BEQ, 1'bx}: next_pc = Z ? PC + 1'b1 + sximm8[8:0] : PC + 1'b1;
	{3'b001, 2'b0, `BNE, 1'bx}: next_pc = Z ? PC + 1'b1 : PC + 1'b1 + sximm8[8:0]; 
	{3'b001, 2'b0, `BLT, 1'bx}: next_pc = (N!==V) ? PC + 1'b1 + sximm8[8:0] : PC + 1'b1;
	{3'b001, 2'b0, `BLE, 1'bx}: next_pc = (N!== V || Z) ? PC + 1'b1 + sximm8[8:0] : PC + 1'b1;
	
	default: next_pc = PC + 1'b1;
	
	endcase
end

endmodule
