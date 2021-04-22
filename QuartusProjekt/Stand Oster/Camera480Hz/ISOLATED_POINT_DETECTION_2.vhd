-- Design Name	: ISOLATED_POINT_DETEDTION_2
-- File Name	: ISOLATED_POINT_DETEDTION_2.vhd
-- Function		: detection of isolated points in a line of a imagine
-- Coder			: Lukas Herbst


library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;
use ieee.math_real.all; 
use work.func_pack.all;


entity ISOLATED_POINT_DETECTION_2 is
generic(
	NUMBERS_OF_OBJECTS	: POSITIVE := 3;		-- number of isolated points / objects, that can be detected  (max: 3)
	THRESHOLD				: POSITIVE := 300;	-- threshold for object-detection
	RES_WIDTH				: POSITIVE := 640		-- Resolution x
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
	det_obj_cnt_out			: out unsigned (1 downto 0); 											-- count detected object
	det_obj_x_pos_1_out		: out unsigned (9 downto 0);											-- x-pos of first detected object
	det_obj_x_pos_2_out		: out unsigned (9 downto 0);											-- x-pos of second detected object
	det_obj_x_pos_3_out		: out unsigned (9 downto 0);											-- x-pos of third detected object
	det_obj_conv_value_1_out: out	signed (9 downto 0);												-- convolution value of first detected object
	det_obj_conv_value_2_out: out	signed (9 downto 0);												-- convolution value of second detected object
	det_obj_conv_value_3_out: out	signed (9 downto 0);												-- convolution value of third detected object
	det_obj_out					: out std_logic_vector ( NUMBERS_OF_OBJECTS - 1 downto 0)	-- shows, that an object was detect	
);
end entity ISOLATED_POINT_DETECTION_2;

architecture a of ISOLATED_POINT_DETECTION_2 is
	type detection_state_machine is (wait_for_first_pixel_state, wait_for_second_pixel_state, wait_for_third_pixel_state, conv_state);
	signal detection_state : detection_state_machine;					-- state machine
	signal data_in_ff_1 			: std_logic_vector (7 downto 0);	
	signal data_in_ff_2 			: std_logic_vector (7 downto 0);	
	signal data_in_ff_3 			: std_logic_vector (7 downto 0);
	signal data_in_valid_ff_1 	: std_logic;
	signal data_in_valid_ff_2 	: std_logic;
	signal det_obj_cnt			: unsigned (1 downto 0); 				-- count detected object
	signal x_pos_in_ff_1			: unsigned (9 downto 0);
	signal x_pos_in_ff_2			: unsigned (9 downto 0);
	signal conv_result			: signed (9 downto 0);
	-- implemented arrays for detected objects
	type det_obj_pos_x_type 		is array (0 to NUMBERS_OF_OBJECTS-1) of unsigned (9 downto 0);
	type det_obj_conv_value_type 	is array (0 to NUMBERS_OF_OBJECTS-1) of signed (9 downto 0);
	signal det_obj_pos_x				: det_obj_pos_x_type;											-- x-position of detected objects
	signal det_obj_conv_value		: det_obj_conv_value_type;										-- convolution value of detected objects
	signal det_obj						: std_logic_vector (NUMBERS_OF_OBJECTS - 1 downto 0);

begin
	-- output signals
	conv_result_out 				<= conv_result;
	det_obj_x_pos_1_out 			<= det_obj_pos_x(0);
	det_obj_x_pos_2_out 			<= det_obj_pos_x(1);
	det_obj_x_pos_3_out 			<= det_obj_pos_x(2);
	det_obj_conv_value_1_out	<= det_obj_conv_value(0);
	det_obj_conv_value_2_out	<= det_obj_conv_value(1);
	det_obj_conv_value_3_out	<= det_obj_conv_value(2);
	det_obj_out 					<= det_obj;
	det_obj_cnt_out				<= det_obj_cnt;
	
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
		conv_result 			<= (others => '0');
		det_obj_cnt				<= (others => '0');
		
		for I in 0 to NUMBERS_OF_OBJECTS - 1 loop
			det_obj_pos_x(I) 			<= (others => '0');
			det_obj_conv_value(I) 	<= (others => '0');
			det_obj(I) 					<= '0';
		end loop;
		

	elsif rising_edge(clk) then
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
					conv_result 		<= (others => '0');
					det_obj_cnt			<= (others => '0');
					
					for I in 0 to NUMBERS_OF_OBJECTS - 1 loop
						det_obj_pos_x(I) 			<= (others => '0');
						det_obj_conv_value(I) 	<= (others => '0');
						det_obj(I) 					<= '0';
					end loop;
					
					detection_state 	<= wait_for_second_pixel_state;
				end if;
			
			when wait_for_second_pixel_state => -- read the second pixel ans it's x-position
					data_in_ff_1 		<= data_in;
					data_in_ff_2		<= data_in_ff_1;
					data_in_ff_3		<= data_in_ff_2;
					x_pos_in_ff_1		<= x_pos_in;
					x_pos_in_ff_2		<= x_pos_in_ff_1;
					detection_state 	<= wait_for_third_pixel_state;
			
			when wait_for_third_pixel_state => -- read the third pixel and it's x-position
					data_in_ff_1 		<= data_in;
					data_in_ff_2		<= data_in_ff_1;
					data_in_ff_3		<= data_in_ff_2;
					x_pos_in_ff_1		<= x_pos_in;
					x_pos_in_ff_2		<= x_pos_in_ff_1;
					detection_state 	<= conv_state;
					
			when conv_state => 
				if x_pos_in_ff_2 = (RES_WIDTH - 1) then -- end of row is reached
					-- reset old Flipflop values
					data_in_ff_1 		<= (others => '0');
					data_in_ff_2 		<= (others => '0');
					data_in_ff_3 		<= (others => '0');
					x_pos_in_ff_1 		<= (others => '0');
					x_pos_in_ff_2 		<= (others => '0');
					detection_state 	<= wait_for_first_pixel_state;
				
				elsif det_obj_cnt < NUMBERS_OF_OBJECTS then -- check, whether maximum numbers of objects are found
					conv_result_var 	:= std_to_sig_resize(data_in_ff_1, 10)  
												- std_to_sig_resize(data_in_ff_2, 10) 
												- std_to_sig_resize(data_in_ff_2, 10) 
												+ std_to_sig_resize(data_in_ff_3, 10);	-- compute convolution of the last 3 pixel (use 2nd derivative)
					conv_result			<=	conv_result_var;
					
						if abs(conv_result_var) >= THRESHOLD then -- check, whether there is an point/object or not
							det_obj_cnt	<= det_obj_cnt + 1;
							if det_obj(0) = '0' then
								det_obj_conv_value(0)	<= abs(conv_result);
								det_obj_pos_x(0) 			<= x_pos_in_ff_2;
								det_obj(0)					<= '1';
							elsif det_obj(1) = '0' then
								det_obj_conv_value(1)	<= abs(conv_result);
								det_obj_pos_x(1) 			<= x_pos_in_ff_2;
								det_obj(1)					<= '1';
							elsif det_obj(2) = '0' then
								det_obj_conv_value(2)	<= abs(conv_result);
								det_obj_pos_x(2) 			<= x_pos_in_ff_2;
								det_obj(2)					<= '1';	
							end if;
						end if;
						
					data_in_ff_1 	<= data_in;
					data_in_ff_2	<= data_in_ff_1;
					data_in_ff_3	<= data_in_ff_2;
					x_pos_in_ff_1	<= x_pos_in;
					x_pos_in_ff_2	<= x_pos_in_ff_1;
				else -- maximum number of objects are found
					-- reset old Flipflop values
					data_in_ff_1 		<= (others => '0');
					data_in_ff_2 		<= (others => '0');
					data_in_ff_3 		<= (others => '0');
					x_pos_in_ff_1 		<= (others => '0');
					x_pos_in_ff_2 		<= (others => '0');
					detection_state 	<= wait_for_first_pixel_state;
				end if;
				
		end case;
	end if;
end process;

end a;