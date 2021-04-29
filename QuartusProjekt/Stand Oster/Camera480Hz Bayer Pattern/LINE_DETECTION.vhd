-- Design Name	: LINE_DETECTION
-- File Name	: LINE_DETECTION.vhd
-- Function		: Detection of a line-object in an imagine line 
-- Coder			: Lukas Herbst


library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;
use ieee.math_real.all; 
use work.func_pack.all;

 
entity LINE_DETECTION is
generic(
	THRESHOLD				: POSITIVE := 100;	-- threshold for object-detection
	RES_WIDTH				: POSITIVE := 640		-- Resolution
);
PORT  
(
	-- INPUT
	clk				: in std_logic;							-- clock
	data_in			: in std_logic_vector (7 downto 0);	-- pixel data (intensity)
	data_in_valid	: in std_logic;							-- indicates valid data
	x_pos_in			: in unsigned (9 downto 0);			-- x-pos (column) of the pixel
	reset				: in std_logic;							-- reset
	
	-- OUTPUT
	conv_result_out			: out signed (9 downto 0);												-- latest convolution result
	det_obj_x_pos_beg_out	: out unsigned (9 downto 0);											-- x-pos of beginning object 	-> first black pixel
	det_obj_x_pos_mid_out	: out unsigned (9 downto 0);											-- x-pos midpoint of object
	det_obj_x_pos_end_out	: out unsigned (9 downto 0);											-- x-pos end of object			-> last black pixel
	det_obj_out					: out std_logic;															-- shows, that an object was detect	
	conv_result_begin_out	: out signed (9 downto 0);
	conv_result_end_out		: out signed (9 downto 0)
	--det_obj_data_out			: out std_logic_vector (7 downto 0);	-- pixel-data of detected isolated point (f(x))
	--det_obj_data_back_out	: out std_logic_vector (7 downto 0)	-- pixel-data of detected isolated point (f(x+1))
);
end entity LINE_DETECTION;

architecture a of LINE_DETECTION is
	type detection_state_machine is	(wait_for_first_pixel_state, wait_for_second_pixel_state,  detect_start_of_line_state, detect_end_of_line_state);
								
	signal detection_state : detection_state_machine;
	signal data_in_ff_1 			: std_logic_vector (7 downto 0);	
	signal data_in_ff_2 			: std_logic_vector (7 downto 0);	
	signal data_in_valid_ff_1 	: std_logic;
	signal data_in_valid_ff_2 	: std_logic;
	signal x_pos_in_ff_1			: unsigned (9 downto 0);
	signal x_pos_in_ff_2			: unsigned (9 downto 0);
	signal det_obj_x_pos_beg	: unsigned (9 downto 0);		
	signal det_obj_x_pos_mid	: unsigned (9 downto 0);	
	signal det_obj_x_pos_end	: unsigned (9 downto 0);	
	signal det_obj					: std_logic;
	signal conv_result_begin	: signed (9 downto 0);
	signal conv_result_end		: signed (9 downto 0);
	signal conv_result			: signed (9 downto 0);
	--signal det_obj_data			: std_logic_vector (7 downto 0);
	--signal det_obj_data_back	: std_logic_vector (7 downto 0); 
	

begin
	conv_result_out 				<= conv_result;
	conv_result_begin_out		<= conv_result_begin;
	conv_result_end_out			<= conv_result_end;
	det_obj_x_pos_beg_out 		<= det_obj_x_pos_beg;
	det_obj_x_pos_mid_out 		<= det_obj_x_pos_mid;
	det_obj_x_pos_end_out 		<= det_obj_x_pos_end;
	det_obj_out 					<= det_obj;
	--det_obj_data_out				<= det_obj_data;
	--det_obj_data_back_out		<= det_obj_data_back;
	
process (reset, clk) is
	variable conv_result_var	: signed (9 downto 0) ;
begin
	if reset = '1' then	-- reset all values
		detection_state		<= wait_for_first_pixel_state;
		data_in_ff_1 			<= (others => '0');
		data_in_ff_2 			<= (others => '0');
		data_in_valid_ff_1	<= '0';
		data_in_valid_ff_2	<= '0';
		x_pos_in_ff_1 			<= (others => '0');
		x_pos_in_ff_2 			<= (others => '0');
		det_obj_x_pos_beg 	<= (others => '0');
		det_obj_x_pos_mid 	<= (others => '0');
		det_obj_x_pos_end 	<= (others => '0');
		conv_result_begin		<= (others => '0');
		conv_result_end		<= (others => '0');
		conv_result 			<= (others => '0');
		det_obj 					<= '0';
		--det_obj_data			<= (others => '0');
		--det_obj_data_back		<= (others => '0');
	

	elsif rising_edge(clk) then
		data_in_valid_ff_1 <= data_in_valid;
		data_in_valid_ff_2 <= data_in_valid_ff_1;
	
		case detection_state is 
		
			when wait_for_first_pixel_state => -- read the first pixel and it's x-position and reset old values
				if data_in_valid_ff_1 = '1' and data_in_valid_ff_2 = '0' then
					data_in_ff_1 			<= data_in;
					data_in_ff_2			<= data_in_ff_1;
					x_pos_in_ff_1			<= x_pos_in;
					x_pos_in_ff_2			<= x_pos_in_ff_1;
					det_obj_x_pos_beg 	<= (others => '0');
					det_obj_x_pos_mid 	<= (others => '0');
					det_obj_x_pos_end 	<= (others => '0');
					conv_result_begin		<= (others => '0');
					conv_result_end		<= (others => '0');
					conv_result 			<= (others => '0');
					det_obj 					<= '0';
					--det_obj_data			<= (others => '0');
					--det_obj_data_back		<= (others => '0');
					detection_state 	<= wait_for_second_pixel_state;
				end if;
			
			when wait_for_second_pixel_state => -- read the second pixel ans it's x-position
					data_in_ff_1 		<= data_in;
					data_in_ff_2		<= data_in_ff_1;
					x_pos_in_ff_1		<= x_pos_in;
					x_pos_in_ff_2		<= x_pos_in_ff_1;
					detection_state 	<= detect_start_of_line_state;
						
			when detect_start_of_line_state =>		
				if x_pos_in_ff_1 = (RES_WIDTH - 1) then -- end of row is reached
					-- reset old flipflop values
					data_in_ff_1 		<= (others => '0');
					data_in_ff_2 		<= (others => '0');
					x_pos_in_ff_1 		<= (others => '0');
					x_pos_in_ff_2 		<= (others => '0');
					detection_state 	<= wait_for_first_pixel_state;
				else	-- compute the convolution (use 1st derivative)  and read the next pixel
					conv_result_var 	:= std_to_sig_resize(data_in_ff_1, 10)  -  std_to_sig_resize(data_in_ff_2, 10);-- - std_to_sig_resize(data_in_ff_2, 10) + std_to_sig_resize(data_in_ff_3, 10);
					conv_result			<=	conv_result_var;
					data_in_ff_1 	<= data_in;
					data_in_ff_2	<= data_in_ff_1;
					x_pos_in_ff_1	<= x_pos_in;
					x_pos_in_ff_2	<= x_pos_in_ff_1;
					if conv_result_var <= (- THRESHOLD) then
						conv_result_begin	<= abs(conv_result_var);
						det_obj_x_pos_beg	<= x_pos_in_ff_1;
						detection_state	<= detect_end_of_line_state;
						--det_obj_data		<= data_in_ff_2;
						--det_obj_data_back	<= data_in_ff_1;
					end if;
				end if;
						
			when detect_end_of_line_state => 
				if x_pos_in_ff_1 = (RES_WIDTH - 1) then -- end of row is reached
					-- reset old flipflop values
					data_in_ff_1 		<= (others => '0');
					data_in_ff_2 		<= (others => '0');
					x_pos_in_ff_1 		<= (others => '0');
					x_pos_in_ff_2 		<= (others => '0');
					detection_state 	<= wait_for_first_pixel_state;
					det_obj_x_pos_end <= x_pos_in_ff_1;
				else	-- compute the convolution (use 1st derivative) and read the next pixel
					conv_result_var 	:= std_to_sig_resize(data_in_ff_1, 10)  -  std_to_sig_resize(data_in_ff_2, 10);-- - std_to_sig_resize(data_in_ff_2, 10) + std_to_sig_resize(data_in_ff_3, 10);
					conv_result			<=	abs(conv_result_var);
					data_in_ff_1 		<= data_in;
					data_in_ff_2		<= data_in_ff_1;
					x_pos_in_ff_1		<= x_pos_in;
					x_pos_in_ff_2		<= x_pos_in_ff_1;
					if conv_result_var >= THRESHOLD then -- detect end of line-object
						detection_state	<= wait_for_first_pixel_state;
						conv_result_end	<= conv_result_var;
						det_obj				<= '1';
						det_obj_x_pos_end <= x_pos_in_ff_2;
						det_obj_x_pos_mid <= (x_pos_in_ff_2 + det_obj_x_pos_beg)/ 2;
					end if;
				end if;
		end case;		
	end if;
end process;

end a;