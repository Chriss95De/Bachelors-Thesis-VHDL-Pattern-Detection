-- Design Name	: CTU_VGA_V3_state_machine
-- File Name	: CTU_VGA_V3_state_machine.vhd
-- Function		: Counts the line in which the vga output is located
-- Coder			: Lukas Herbst

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity CTU_VGA_V3_state_machine is

generic (
	RES_HEIGHT	:	POSITIVE:= 480;		-- Resolution x
	V_FP	 		:	INTEGER := 10;			-- vertical front porch width in rows
	V_PULSE 		:	INTEGER := 2;			-- vertical sync pulse width in rows
	V_BP	 		:	INTEGER := 33			-- vertical back porch width in rows
);

port  
(
	clk				: in std_logic;				-- clock for increment
	disp_ena			: in std_logic;				-- start signal for a new frame by first rising edge after reset counter
	h_sync_inc		: in std_logic;				--	increment counter 
	v_sync_reset	: in std_logic;				-- reset counter, if a new fram is requested
	reset				: in std_logic;				-- reset all
	vga_line_y		: out unsigned(8 DOWNTO 0)	-- data at current coordinate
);
end entity CTU_VGA_V3_state_machine;


architecture a of CTU_VGA_V3_state_machine is
	type counter_state_machine is (wait_for_first_line, count_lines, reset_counter); -- state of the state_machine
	signal counter_state : counter_state_machine;		-- state machine
	signal vga_line_y_next  	: unsigned(8 downto 0); -- next output value
	signal disp_ena_ff_1			: std_logic;				-- synchronized start signal	-> output-signal of disp_ena-flipflop 1
	signal disp_ena_ff_2			: std_logic;				-- synchronized start signal	-> output-signal of disp_ena-flipflop 2
	signal h_sync_inc_ff_1 		: std_logic; 				-- synchronized increment signal -> output-signal of h_sync_inc-flipflop 1
	signal h_sync_inc_ff_2 		: std_logic;				-- synchronized increment signal -> output-signal of h_sync_inc-flipflop 2
	signal v_sync_reset_ff_1	: std_logic;				-- synchronized reset_counter -> output-signal of v_sync_reset-flipflop 1
	signal v_sync_reset_ff_2	: std_logic;				-- synchronized reset_counter -> output-signal of v_sync_reset-flipflop 2

begin
	vga_line_y <= vga_line_y_next;							-- send vga_line_y_next to output

process (clk, reset) is
begin
	
	if reset = '1' then											-- reset
		counter_state <= wait_for_first_line;				-- go back into start state
		vga_line_y_next <= (others =>'0');					-- reset value of vga_line_y_next
		--reset all flipflop-outputs
		disp_ena_ff_1 <= '0';
		disp_ena_ff_2 <= '0';
		h_sync_inc_ff_1 <= '0';
		h_sync_inc_ff_2 <= '0';
		v_sync_reset_ff_1 <= '0';
		v_sync_reset_ff_2 <= '0';
			
	elsif rising_edge (clk) then
		disp_ena_ff_1 <= disp_ena;								-- generate disp_ena-flipflop 1
		disp_ena_ff_2 <= disp_ena_ff_1;						-- generate disp_ena-flipflop 2
		h_sync_inc_ff_1 <= h_sync_inc;						-- generate h_sync_inc-flipflop 1
		h_sync_inc_ff_2 <= h_sync_inc_ff_1;					-- generate h_sync_inc-flipflop 2
		v_sync_reset_ff_1 <= v_sync_reset;					-- generate v_sync_reset-flipflop 1
		v_sync_reset_ff_2 <= v_sync_reset_ff_1;			-- generate v_sync_reset-flipflop 2
		
		-- state-machine
		case counter_state is
		
		when wait_for_first_line =>  -- wait for signal change of disp_ena from '0' to '1'
			if disp_ena_ff_2 = '0' and disp_ena_ff_1 = '1' then -- signal change of disp_ena indicates a new line
				counter_state <= count_lines;							 -- go into next state count_lines
			end if;
			
		when count_lines => -- count lines by every signal change of h_sync_inc from '0' to '1'
			if h_sync_inc_ff_2 = '0' and h_sync_inc_ff_1 = '1' then
				if vga_line_y_next + 1 = (RES_HEIGHT) then				-- if last line of frame is reached, go into next state; reset_counter
					counter_state <= reset_counter;
				else vga_line_y_next <= vga_line_y_next + 1;				-- increment line			
				end if;
			end if;
		
		when reset_counter => -- reset counter by signal change of v_sync_reset from '0' to '1' and go into state wait_for_first_line
			if v_sync_reset_ff_2 = '0' and v_sync_reset_ff_1 = '1' then
				vga_line_y_next <= (others => '0');
				counter_state <= wait_for_first_line;
			end if;
		
		end case;
		
	end if;
		
end process;

end a;