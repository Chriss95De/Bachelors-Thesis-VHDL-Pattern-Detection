library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; 
library altera_mf;
use altera_mf.altera_mf_components.all;

entity DEBUG_OBJ_DETECTION is 
generic (
	ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
	ADDR_Y_WIDTH				: POSITIVE:= 9 	-- Width of the y address line
	
	);
port (	
	
	-- current center position
	pxl_center_x		: in unsigned(ADDR_X_WIDTH-1 downto 0);
	pxl_center_y		: in unsigned(ADDR_Y_WIDTH-1 downto 0);
	
	det_obj_x_pos_beg		: in unsigned (9 downto 0);										
	det_obj_x_pos_mid		: in unsigned (9 downto 0);
	det_obj_x_pos_end		: in unsigned (9 downto 0);
	
	-- color in
	R				: in std_logic_vector(7 downto 0);
	G				: in std_logic_vector(7 downto 0);
	B				: in std_logic_vector(7 downto 0);
	
	-- color out
	R_out			: out std_logic_vector(7 downto 0);
	G_out			: out std_logic_vector(7 downto 0);
	B_out			: out std_logic_vector(7 downto 0)
	 
	); 
end entity DEBUG_OBJ_DETECTION;
	
	
architecture a of DEBUG_OBJ_DETECTION is	
begin

	--colored line begining
	R_out <= (others => '0') when unsigned(pxl_center_x) = unsigned(det_obj_x_pos_beg) or unsigned(pxl_center_x) = unsigned(det_obj_x_pos_end) 
	else R;
	
	G_out <= (others => '1') when unsigned(pxl_center_x) = unsigned(det_obj_x_pos_beg) or unsigned(pxl_center_x) = unsigned(det_obj_x_pos_end) 
	else G;
	
	B_out <= (others => '0') when unsigned(pxl_center_x) = unsigned(det_obj_x_pos_beg) or unsigned(pxl_center_x) = unsigned(det_obj_x_pos_end) 
	else B;
	
	
end a;