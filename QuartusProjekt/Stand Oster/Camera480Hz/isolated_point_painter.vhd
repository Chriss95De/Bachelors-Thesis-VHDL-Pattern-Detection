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
generic(
	THRESHOLD	: POSITIVE := 300;	-- threshold for object-detection
	RES_WIDTH	: POSITIVE := 640		-- Resolution x
);
PORT  
(
	-- INPUT
	x_pos_in			: IN unsigned (9 downto 0);			-- x-pos (column) of the pixel
	reset				: IN std_logic;							-- reset
	
	pixel_clk		:	IN	STD_LOGIC;	--pixel clock at frequency of VGA mode being used
	vga_data_in		: 	IN STD_LOGIC_VECTOR (7 downto 0);	-- pixel data (intensity)
	h_sync_in		:	IN	STD_LOGIC;	--horiztonal sync pulse
	v_sync_in		:	IN	STD_LOGIC;	--vertical sync pulse
	disp_ena_in		:	IN	STD_LOGIC;	--display enable ('1' = display time, '0' = blanking time)
	column_in		:	IN	INTEGER;		--horizontal pixel coordinate
	row_in			:	IN	INTEGER;		--vertical pixel coordinate
	n_blank_in		:	IN	STD_LOGIC;	--direct blacking output to DAC
	n_sync_in		:	IN	STD_LOGIC; --sync-on-green output to DAC
	
	-- OUTPUT
	h_sync		:	OUT	STD_LOGIC;	--horiztonal sync pulse
	v_sync		:	OUT	STD_LOGIC;	--vertical sync pulse
	disp_ena		:	OUT	STD_LOGIC;	--display enable ('1' = display time, '0' = blanking time)
	column		:	OUT	INTEGER;		--horizontal pixel coordinate
	row			:	OUT	INTEGER;		--vertical pixel coordinate
	n_blank		:	OUT	STD_LOGIC;	--direct blacking output to DAC
	n_sync		:	OUT	STD_LOGIC; --sync-on-green output to DAC
	vgb_r			:  OUT	STD_LOGIC_VECTOR (7 downto 0); --red out
	vgb_g			:  OUT	STD_LOGIC_VECTOR (7 downto 0); --green out
	vgb_b			:  OUT	STD_LOGIC_VECTOR (7 downto 0) --blue out
	
);
end entity ISOLATED_POINT_PAINTER;

architecture a of ISOLATED_POINT_PAINTER is
	SIGNAL x_pos_ff		: unsigned (9 downto 0);			-- x-pos (column) of the pixel
	SIGNAL vga_data_ff	: STD_LOGIC_VECTOR (7 downto 0);	-- pixel data (intensity)
	SIGNAL h_sync_ff		: STD_LOGIC;	--horiztonal sync pulse
	SIGNAL v_sync_ff		: STD_LOGIC;	--vertical sync pulse
	SIGNAL disp_ena_ff	: STD_LOGIC;	--display enable ('1' = display time, '0' = blanking time)
	SIGNAL column_ff		: INTEGER;		--horizontal pixel coordinate
	SIGNAL row_ff			: INTEGER;		--vertical pixel coordinate
	SIGNAL n_blank_ff		: STD_LOGIC;	--direct blacking output to DAC
	SIGNAL n_sync_ff		: STD_LOGIC; --sync-on-green output to DAC
	
begin

	--output
	h_sync		<= h_sync_ff;
	v_sync		<= v_sync_ff;
	disp_ena		<= disp_ena_ff;
	column		<= column_ff;
	row			<= row_ff;
	n_blank		<= n_blank_ff;
	n_sync		<= n_sync_ff;
	vgb_r			<= vga_data_ff;
	vgb_g			<= vga_data_ff;
	vgb_b			<= vga_data_ff;
	
	
process (reset, pixel_clk) is
	variable conv_result_var	: signed (9 downto 0) ;
	
begin
	if reset = '1' then	-- reset all values
		h_sync_ff		<= '0';
		v_sync_ff		<= '0';
		disp_ena_ff		<= '0';
		column_ff		<= 0;
		row_ff			<= 0;
		n_blank_ff		<= '0';
		n_sync_ff		<= '0';
		vga_data_ff		<= (others => '0');
		--vgb_r			<= (others => '0');
		--vgb_g			<= (others => '0');
		--vgb_b			<= (others => '0');
		
	elsif rising_edge(pixel_clk) then
		-- sync
		x_pos_ff		<= x_pos_in;
		vga_data_ff	<= vga_data_in;
		h_sync_ff	<= h_sync_in;
		v_sync_ff	<= v_sync_ff;
		disp_ena_ff	<= disp_ena_in;
		column_ff	<= column_in;
		row_ff		<= row_in;
		n_blank_ff	<= n_blank_in;
		n_sync_ff	<= n_sync_in;
		
	end if;
end process;

end a;