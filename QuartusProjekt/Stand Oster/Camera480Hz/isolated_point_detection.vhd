-- Design Name	: isolated_point_detection
-- File Name	: isolated_point_detection.vhd
-- Function		: detection of isolated point in a line of a imagine
-- Coder			: Lukas Herbst


library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;
use ieee.math_real.all; 
use work.func_pack.all;


entity ISOLATED_POINT_DETECTION is
generic(
	THRESHOLD	: POSITIVE := 300;	-- threshold for object-detection
	RES_WIDTH	: POSITIVE := 640		-- Resolution x
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
	conv_result_out			: out signed (9 downto 0);					-- latest convolution result
	det_obj_x_pos_out			: out unsigned (9 downto 0);				-- x-pos of detected object
	det_obj_conv_value_out	: out	signed (9 downto 0);					-- convolution value of detected object
	det_obj_out					: out std_logic;								-- shows, that an object was detect
	det_obj_data_out			: out std_logic_vector (7 downto 0)		-- pixel-data of detected isolated point (f(x))
	-- det_obj_data_front_out	: out std_logic_vector (7 downto 0);	-- pixel-data of detected isolated point (f(x-1))
	-- det_obj_data_back_out	: out std_logic_vector (7 downto 0)		-- pixel-data of detected isolated point (f(x+1))
	
);
end entity ISOLATED_POINT_DETECTION;

architecture a of ISOLATED_POINT_DETECTION is
	type detection_state_machine is (wait_for_first_pixel_state, wait_for_second_pixel_state, wait_for_third_pixel_state, conv_state);
	signal detection_state : detection_state_machine;
	signal data_in_ff_1 			: std_logic_vector (7 downto 0);	
	signal data_in_ff_2 			: std_logic_vector (7 downto 0);	
	signal data_in_ff_3 			: std_logic_vector (7 downto 0);
	signal data_in_valid_ff_1 	: std_logic;
	signal data_in_valid_ff_2 	: std_logic;
	signal x_pos_in_ff_1			: unsigned (9 downto 0);
	signal x_pos_in_ff_2			: unsigned (9 downto 0);
	signal x_pos_in_ff_3			: unsigned (9 downto 0);
	signal conv_result			: signed (9 downto 0);
	signal det_obj_pos_x			: unsigned (9 downto 0);			-- x-position of detected object
	signal det_obj_conv_value	: signed (9 downto 0);				-- convolution value of detected objects
	signal det_obj					: std_logic;
	signal det_obj_data			: std_logic_vector (7 downto 0);	-- data of detected object
	-- signal det_obj_data_front	: std_logic_vector (7 downto 0); 
	-- signal det_obj_data_back	: std_logic_vector (7 downto 0); 
	
begin
	-- signal to output
	conv_result_out 				<= conv_result;
	det_obj_x_pos_out 			<= det_obj_pos_x;
	det_obj_conv_value_out		<= det_obj_conv_value;
	det_obj_out 					<= det_obj;
	det_obj_data_out				<= det_obj_data;
	-- det_obj_data_front_out		<= det_obj_data_front;
	-- det_obj_data_back_out		<= det_obj_data_back;
	
process (reset, clk) is
	variable conv_result_var	: signed (9 downto 0) ;
	
begin
	if reset = '1' then	-- reset all values
		detection_state		<= wait_for_first_pixel_state;
		data_in_ff_1 			<= (others => '0');
		data_in_ff_2 			<= (others => '0');
		data_in_ff_3 			<= (others => '0');
		data_in_valid_ff_1	<= '0';
		data_in_valid_ff_2	<= '0';
		x_pos_in_ff_1 			<= (others => '0');
		x_pos_in_ff_2 			<= (others => '0');
		x_pos_in_ff_3 			<= (others => '0');
		conv_result 			<= (others => '0');
		det_obj_pos_x 			<= (others => '0');
		det_obj_conv_value 	<= (others => '0');
		det_obj 					<= '0';
		det_obj_data			<= (others => '0');
		-- det_obj_data_front	<= (others => '0');
		-- det_obj_data_back		<= (others => '0');
		
	elsif rising_edge(clk) then
		-- synchronize data_in_valid
		data_in_valid_ff_1 <= data_in_valid;
		data_in_valid_ff_2 <= data_in_valid_ff_1;
	
		case detection_state is 
		
			when wait_for_first_pixel_state => -- read the first pixel and it's x-position and reset old values
				if data_in_valid_ff_1 = '1' and data_in_valid_ff_2 = '0' then
					data_in_ff_1 		<= data_in;
					data_in_ff_2		<= data_in_ff_1;
					data_in_ff_3		<= data_in_ff_2;
					x_pos_in_ff_1		<= x_pos_in;
					x_pos_in_ff_2		<= x_pos_in_ff_1;
					x_pos_in_ff_3		<= x_pos_in_ff_2;
					
					conv_result 			<= (others => '0');
					det_obj_pos_x 			<= (others => '0');
					det_obj_conv_value 	<= (others => '0');
					det_obj 					<= '0';
					det_obj_data			<= (others => '0');
					-- det_obj_data_front	<= (others => '0');
					-- det_obj_data_back		<= (others => '0');
					
					detection_state 	<= wait_for_second_pixel_state;
				end if;
			
			when wait_for_second_pixel_state => -- read the second pixel ans it's x-position
					data_in_ff_1 		<= data_in;
					data_in_ff_2		<= data_in_ff_1;
					data_in_ff_3		<= data_in_ff_2;
					x_pos_in_ff_1		<= x_pos_in;
					x_pos_in_ff_2		<= x_pos_in_ff_1;
					x_pos_in_ff_3		<= x_pos_in_ff_2;
					detection_state 	<= wait_for_third_pixel_state;
			
			when wait_for_third_pixel_state => -- read the third pixel and it's x-position
					data_in_ff_1 		<= data_in;
					data_in_ff_2		<= data_in_ff_1;
					data_in_ff_3		<= data_in_ff_2;
					x_pos_in_ff_1		<= x_pos_in;
					x_pos_in_ff_2		<= x_pos_in_ff_1;
					x_pos_in_ff_3		<= x_pos_in_ff_2;
					detection_state 	<= conv_state;
					
			when conv_state => 
				if x_pos_in_ff_2 = (RES_WIDTH - 1) then -- end of row is reached
					-- reset old Flipflop values
					data_in_ff_1 		<= (others => '0');
					data_in_ff_2 		<= (others => '0');
					data_in_ff_3 		<= (others => '0');
					x_pos_in_ff_1 		<= (others => '0');
					x_pos_in_ff_2 		<= (others => '0');
					x_pos_in_ff_3 		<= (others => '0');
					detection_state 	<= wait_for_first_pixel_state;
					
				else  -- compute convolution of the last 3 pixel (use 2nd derivative)
					conv_result_var 	:= std_to_sig_resize(data_in_ff_1, 10)  
												- std_to_sig_resize(data_in_ff_2, 10) 
												- std_to_sig_resize(data_in_ff_2, 10) 
												+ std_to_sig_resize(data_in_ff_3, 10);
					conv_result			<=	conv_result_var;
		
					if abs(conv_result_var) >= THRESHOLD then -- check, whether there is an isolated point/object or not
						-- detected object
						det_obj_conv_value	<= abs(conv_result_var);
						det_obj_pos_x 			<= x_pos_in_ff_2;
						det_obj					<= '1';
						det_obj_data			<= data_in_ff_2; -- f(x) -> detected point
						-- det_obj_data_front	<= data_in_ff_3; -- f(x-1)
						-- det_obj_data_back		<= data_in_ff_1; -- f(x+1)
					
						-- reset old Flipflop values
						data_in_ff_1 		<= (others => '0');
						data_in_ff_2 		<= (others => '0');
						data_in_ff_3 		<= (others => '0');
						x_pos_in_ff_1 		<= (others => '0');
						x_pos_in_ff_2 		<= (others => '0');
						x_pos_in_ff_3 		<= (others => '0');
						detection_state 	<= wait_for_first_pixel_state;
				
					else	-- read the next pixel
						data_in_ff_1 	<= data_in;
						data_in_ff_2	<= data_in_ff_1;
						data_in_ff_3	<= data_in_ff_2;
						x_pos_in_ff_1	<= x_pos_in;
						x_pos_in_ff_2	<= x_pos_in_ff_1;
						x_pos_in_ff_3	<= x_pos_in_ff_2;
					end if;
				end if;
		end case;
	end if;
end process;

end a;