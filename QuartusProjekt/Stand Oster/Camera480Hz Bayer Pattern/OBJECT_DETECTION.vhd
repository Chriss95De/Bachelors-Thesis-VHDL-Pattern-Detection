-- Design Name	: OBJECT_DETECTION
-- Function		: 
-- Coder			: Christian Oster
-- Date			: 10.06.2021
--
--	Description	: 



library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; 
library altera_mf;
use altera_mf.altera_mf_components.all;

entity OBJECT_DETECTION is 
generic (
	THRESHOLD				: POSITIVE := 80;	-- threshold for object-detection
	RES_WIDTH				: POSITIVE := 640;		-- Resolution x
	RES_HEIGHT				: POSITIVE := 480;		-- Resolution y

	ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
	ADDR_Y_WIDTH				: POSITIVE:= 9 	-- Width of the y address line
	
	);
port (	

	clk				: in std_logic;							-- clock
	reset				: in std_logic;							-- reset
	
	det_obj_x_pos_beg		: in unsigned (9 downto 0);
	det_obj_x_pos_end		: in unsigned (9 downto 0);
	det_obj_found			: in std_logic;
	
	obj_center_x			: out unsigned(ADDR_X_WIDTH-1 downto 0);
	obj_center_y			: out unsigned(ADDR_Y_WIDTH-1 downto 0)
	 
	); 
end entity OBJECT_DETECTION;
	
	
architecture a of OBJECT_DETECTION is	

	
 
begin
process (reset, clk) is
	variable conv_result_b	: unsigned (ADDR_Y_WIDTH-1 downto 0);
	begin
	if reset = '1' then	-- reset all values
		
		
	elsif rising_edge(clk) then	
		
	end if;
	
end process;
end architecture a;