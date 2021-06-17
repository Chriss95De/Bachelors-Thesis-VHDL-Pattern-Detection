library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; 
library altera_mf;
use altera_mf.altera_mf_components.all;

entity POSITION_MINDIFF_OUT is 
generic (
	ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
	ADDR_Y_WIDTH				: POSITIVE:= 9; 	-- Width of the y address line
	NEEDED_DIFF					: POSITIVE:= 10
	
	);
port (	
	
	clk				: in std_logic;							-- clock
	reset				: in std_logic;							-- reset
	
	-- current center position
									
	obj_x_pos_in		: in unsigned(ADDR_X_WIDTH-1 downto 0);
	obj_y_pos_in		: in unsigned(ADDR_Y_WIDTH-1 downto 0);
	
	-- color out
	obj_x_pos_out		: out unsigned(ADDR_X_WIDTH-1 downto 0);
	obj_y_pos_out		: out unsigned(ADDR_Y_WIDTH-1 downto 0)
	
	 
	); 
end entity POSITION_MINDIFF_OUT;
	
	
architecture a of POSITION_MINDIFF_OUT is	

signal x_out_ff1 		: unsigned (ADDR_X_WIDTH-1 downto 0);
signal y_out_ff1 		: unsigned (ADDR_Y_WIDTH-1 downto 0);
	
begin
process (reset, clk) is
begin
	if reset = '1' then	-- reset all values
	
		obj_x_pos_out <= (others => '0');
		obj_y_pos_out <= (others => '0');
		
	elsif rising_edge(clk) then
	
		x_out_ff1 <= obj_x_pos_in;
		y_out_ff1 <= obj_y_pos_in;
		
		obj_x_pos_out <= obj_x_pos_out;
		
		if(abs(to_integer(x_out_ff1)-to_integer(obj_x_pos_in)) >= NEEDED_DIFF) then
			obj_x_pos_out <= obj_x_pos_in;
		end if;
			
		if(abs(to_integer(y_out_ff1)-to_integer(obj_y_pos_in)) >= NEEDED_DIFF) then
			obj_y_pos_out <= obj_y_pos_in;
		end if;	
		
	end if;
end process;
	
	
end architecture a;