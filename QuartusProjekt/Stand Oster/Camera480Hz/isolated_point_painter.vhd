-- Design Name	: isolated_point_painter
-- File Name	: isolated_point_painter.vhd
-- Function		: makes a column noticable in vga output by giving it a specific colour
-- Coder			: Christian Oster


library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;
use ieee.math_real.all; 
use work.func_pack.all;


entity ISOLATED_POINT_PAINTER is
PORT  
(
	-- INPUT
	x_pos_in			: IN unsigned (9 downto 0);			-- x-pos (column) of the pixel
	reset				: IN std_logic;							-- reset
	
	pixel_clk_in	:	IN	STD_LOGIC;	--pixel clock at frequency of VGA mode being used
	vga_data_in		: 	IN STD_LOGIC_VECTOR (7 downto 0);	-- pixel data (intensity)
	column_in		:	IN	INTEGER;		--horizontal pixel coordinate
	row_in			:	IN	INTEGER;		--vertical pixel coordinate
	
	-- OUTPUT
	vgb_r			:  OUT	STD_LOGIC_VECTOR (7 downto 0); --red out
	vgb_g			:  OUT	STD_LOGIC_VECTOR (7 downto 0); --green out
	vgb_b			:  OUT	STD_LOGIC_VECTOR (7 downto 0) --blue out
	
);
end entity ISOLATED_POINT_PAINTER;

architecture a of ISOLATED_POINT_PAINTER is
	SIGNAL x_pos_ff		: unsigned (9 downto 0);			-- x-pos (column) of the pixel
	SIGNAL vga_data_ff	: STD_LOGIC_VECTOR (7 downto 0);	-- pixel data (intensity)
	SIGNAL column_ff		: INTEGER;		--horizontal pixel coordinate
	SIGNAL row_ff			: INTEGER;		--vertical pixel coordinate
	
begin

	--output
	--vgb_r	 	<=	vga_data_in;
	--vgb_g		<=	vga_data_in;
	--vgb_b		<=	vga_data_in;
	
	
process (reset, pixel_clk_in) is
begin
	if reset = '1' then	-- reset all values
		vga_data_ff		<= (others => '0');
		
	elsif rising_edge(pixel_clk_in) then
		
		if(to_integer(x_pos_in) = column_in) then
			vgb_r	 	<=	(others => '1');
			vgb_g		<=	(others => '0');
			vgb_b		<=	(others => '0');
		else
			vgb_r	 	<=	vga_data_in;
			vgb_g		<=	vga_data_in;
			vgb_b		<=	vga_data_in;
		end if;
		
	end if;
end process;

end a;