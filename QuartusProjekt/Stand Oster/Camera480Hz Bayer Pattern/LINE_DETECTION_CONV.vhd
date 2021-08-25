-- Design Name	: Function Package
-- Function		: Detection of line-objects in an imagine line 
-- Coder			: Christian Oster
-- Date			: 20.05.2021
--
--	Description	: 
--	Find start and end of and object by change of color compared to background and object.
-- Trys to find  start and end line by line, object detection should be done in another module 
-- to determine the y size of it for example.


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; 
library altera_mf;
use altera_mf.altera_mf_components.all;

entity LINE_DETECTION_CONV is 
generic (
	--THRESHOLD				: POSITIVE := 100;	-- threshold for object-detection
	RES_WIDTH				: POSITIVE := 640;		-- Resolution x
	RES_HEIGHT				: POSITIVE := 480;		-- Resolution y

	ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
	ADDR_Y_WIDTH				: POSITIVE:= 9 	-- Width of the y address line
	
	);
port (	

	clk				: in std_logic;							-- clock
	reset				: in std_logic;							-- reset
	
	-- current center position
	pxl_pos_x		: in unsigned(ADDR_X_WIDTH-1 downto 0);
	pxl_pos_y		: in unsigned(ADDR_Y_WIDTH-1 downto 0);
	
	-- Red
	R				: in std_logic_vector(7 downto 0);
	G				: in std_logic_vector(7 downto 0);
	B				: in std_logic_vector(7 downto 0);
	
	threshold 	: in unsigned(7 downto 0);
	
	pixel_data_valid : in std_logic;
	
	
	
	--Output
	det_obj_x_pos_beg		: out unsigned (9 downto 0);											-- x-pos of beginning object 	-> first black pixel
	det_obj_x_pos_end		: out unsigned (9 downto 0);
	det_obj_conv			: out std_logic_vector (7 downto 0);
	det_obj_found			: out std_logic;
	
	cur_pxl_pos_x			: out unsigned(ADDR_X_WIDTH-1 downto 0);
	cur_pxl_pos_y			: out unsigned(ADDR_Y_WIDTH-1 downto 0);

	debug_out 				: out std_logic_vector(7 downto 0)
	 
	); 
end entity LINE_DETECTION_CONV;
	
	
architecture a of LINE_DETECTION_CONV is	

	--line detection vars
	type detection_state_machine is	(detect_start_of_line_state, detect_end_of_line_state, rest_state);
	
	signal detection_state		: detection_state_machine;
	
	signal r_ff1 			: std_logic_vector (7 downto 0);
	signal g_ff1 			: std_logic_vector (7 downto 0);		
	signal b_ff1 			: std_logic_vector (7 downto 0);
	
	signal pxl_x_ff1 				: unsigned (ADDR_X_WIDTH-1 downto 0);
	signal pxl_y_ff1				: unsigned (ADDR_Y_WIDTH-1 downto 0);
	
	signal pxl_center_x_ff1		: unsigned (ADDR_X_WIDTH-1 downto 0);
	signal pxl_center_y_ff1		: unsigned (ADDR_Y_WIDTH-1 downto 0);
	
	--func
	function std_to_sig_resize (data_std: std_logic_vector; resize_length: positive) return signed is
		variable sig : signed (9 downto 0);
	begin
		sig 	:=  signed(resize(unsigned(data_std), resize_length));
		return sig;
	end function;
	
	-- avg
	function get_avg(l1,l2,l3 : in std_logic_vector(7 downto 0)) return std_logic_vector is
		variable sum	: unsigned(9 downto 0);
	begin
		sum := 	resize(unsigned(l1), 10)+
					resize(unsigned(l2), 10)+
					resize(unsigned(l2), 10)+ --take l2 twice so can use simple 2^2 shift right division
					resize(unsigned(l3), 10);
		return std_logic_vector(resize(shift_right(sum, 2),8));
	end function;
	 
 
begin
process (reset, clk) is
	variable conv_result_var	: signed (9 downto 0);
	begin
	if reset = '1' then	-- reset all values
		detection_state		<= detect_start_of_line_state;
		
		r_ff1				<= (others => '0');
		g_ff1				<= (others => '0');
		b_ff1				<= (others => '0');
		
		pxl_x_ff1		<= (others => '0');
		pxl_y_ff1		<= (others => '0');
		
		det_obj_x_pos_beg 	<= (others => '0');
		det_obj_x_pos_end 	<= (others => '0');
		
		det_obj_conv  <= (others => '0');
		debug_out <= (others => '0');
		
		det_obj_found <= '0';
		
		
	elsif rising_edge(clk) then

		det_obj_found <= '0'; --reset so only active one clk 
	
		if pixel_data_valid = '1' then
			--ff
			r_ff1 <= R;
			g_ff1 <= G;
			b_ff1 <= B;
			
			pxl_x_ff1 <= pxl_pos_x;
			pxl_y_ff1 <= pxl_pos_y;
			
			det_obj_x_pos_beg <= det_obj_x_pos_beg;
			det_obj_x_pos_end <= det_obj_x_pos_end;
			
			cur_pxl_pos_x <= pxl_x_ff1;
			cur_pxl_pos_y <= pxl_y_ff1;
			
			if debug_out < R then
				debug_out <= R;
			end if;	
				
			--work on detection
			
			case detection_state is 
				when detect_start_of_line_state => 
					--R channel
					--check if r channel differs from one to the next pixel
					if to_integer(unsigned(r_ff1)) >= +to_integer(THRESHOLD)  then
							det_obj_x_pos_beg <= pxl_x_ff1;
							detection_state	<= detect_end_of_line_state;
					end if;
				when detect_end_of_line_state => 
					if to_integer(unsigned(r_ff1)) >= +to_integer(THRESHOLD) then --real end found
							det_obj_x_pos_end <= pxl_x_ff1;
							det_obj_found <= '1'; --one clock cycle active!!!
							detection_state <= rest_state;
					end if;
				when rest_state =>
					
			end case;
			
			--reset to detect_start_of_line_state when reached end of the row
			if(pxl_x_ff1 >= (RES_WIDTH - 5)) then
				detection_state	<= detect_start_of_line_state;
			end if;
			
		end if; --end of if pixel_data_valid	
		
	end if;
	
end process;
end architecture a;