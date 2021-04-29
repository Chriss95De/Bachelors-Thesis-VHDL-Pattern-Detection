-- Design Name	: Function Package
-- File Name	: LINE_DETECTION_2.vhd
-- Function		: Detection of line-objects in an imagine line 
-- Coder			: Lukas Herbst
-- Date			: 29.11.2019


library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;
use ieee.math_real.all; 
use work.func_pack.all;

 
entity LINE_DETECTION_2 is
generic(
	NUMBERS_OF_OBJECTS	: POSITIVE := 3;		-- number of lines / objects, that can be detected
	THRESHOLD				: POSITIVE := 100;	-- threshold for object-detection
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
	det_obj_x_pos_beg_1_out	: out unsigned (9 downto 0);											-- x-pos of beginning object 	-> first black pixel
	det_obj_x_pos_mid_1_out	: out unsigned (9 downto 0);											-- x-pos midpoint of object
	det_obj_x_pos_end_1_out	: out unsigned (9 downto 0);											-- x-pos end of object			-> last black pixel
	conv_result_begin_1_out	: out signed (9 downto 0);
	conv_result_end_1_out	: out signed (9 downto 0);
	
	det_obj_x_pos_beg_2_out	: out unsigned (9 downto 0);											-- x-pos of beginning object 	-> first black pixel
	det_obj_x_pos_mid_2_out	: out unsigned (9 downto 0);											-- x-pos midpoint of object
	det_obj_x_pos_end_2_out	: out unsigned (9 downto 0);											-- x-pos end of object			-> last black pixel
	conv_result_begin_2_out	: out signed (9 downto 0);
	conv_result_end_2_out	: out signed (9 downto 0);
	
	det_obj_x_pos_beg_3_out	: out unsigned (9 downto 0);											-- x-pos of beginning object 	-> first black pixel
	det_obj_x_pos_mid_3_out	: out unsigned (9 downto 0);											-- x-pos midpoint of object
	det_obj_x_pos_end_3_out	: out unsigned (9 downto 0);											-- x-pos end of object			-> last black pixel
	conv_result_begin_3_out	: out signed (9 downto 0);
	conv_result_end_3_out	: out signed (9 downto 0);
	
	det_obj_out					: out std_logic_vector (NUMBERS_OF_OBJECTS - 1 downto 0)	-- shows, that objects were detect	
);
end entity LINE_DETECTION_2;

architecture a of LINE_DETECTION_2 is
	type detection_state_machine is	(wait_for_first_pixel_state, wait_for_second_pixel_state,  detect_start_of_line_state, detect_end_of_line_state);
								
	signal detection_state : detection_state_machine;
	signal data_in_ff_1 			: std_logic_vector (7 downto 0);	
	signal data_in_ff_2 			: std_logic_vector (7 downto 0);	
	signal data_in_valid_ff_1 	: std_logic;
	signal data_in_valid_ff_2 	: std_logic;
	signal x_pos_in_ff_1			: unsigned (9 downto 0);
	signal x_pos_in_ff_2			: unsigned (9 downto 0);
	signal det_obj_cnt			: unsigned (1 downto 0); 				-- count detected object
	
	type det_obj_pos_x_type 		is array (0 to NUMBERS_OF_OBJECTS-1) of unsigned (9 downto 0);
	type det_obj_conv_value_type 	is array (0 to NUMBERS_OF_OBJECTS-1) of signed (9 downto 0);
	type det_obj_data_type			is array (0 to NUMBERS_OF_OBJECTS-1) of std_logic_vector (7 downto 0);
	signal det_obj_x_pos_beg	: det_obj_pos_x_type;		
	signal det_obj_x_pos_mid	: det_obj_pos_x_type;	
	signal det_obj_x_pos_end	: det_obj_pos_x_type;
	signal det_obj					: std_logic_vector (NUMBERS_OF_OBJECTS - 1 downto 0);
	signal conv_result_begin	: det_obj_conv_value_type;
	signal conv_result_end		: det_obj_conv_value_type;
	signal conv_result			: signed (9 downto 0);


begin
	-- output signals
	conv_result_out 				<= conv_result;

	det_obj_x_pos_beg_1_out 	<= det_obj_x_pos_beg(0);
	det_obj_x_pos_mid_1_out 	<= det_obj_x_pos_mid(0);
	det_obj_x_pos_end_1_out 	<= det_obj_x_pos_end(0);
	conv_result_begin_1_out		<= conv_result_begin(0);
	conv_result_end_1_out		<= conv_result_end(0);
	
	det_obj_x_pos_beg_2_out 	<= det_obj_x_pos_beg(1);
	det_obj_x_pos_mid_2_out 	<= det_obj_x_pos_mid(1);
	det_obj_x_pos_end_2_out 	<= det_obj_x_pos_end(1);
	conv_result_begin_2_out		<= conv_result_begin(1);
	conv_result_end_2_out		<= conv_result_end(1);
	
	det_obj_x_pos_beg_3_out 	<= det_obj_x_pos_beg(2);
	det_obj_x_pos_mid_3_out 	<= det_obj_x_pos_mid(2);
	det_obj_x_pos_end_3_out 	<= det_obj_x_pos_end(2);
	conv_result_begin_3_out		<= conv_result_begin(2);
	conv_result_end_3_out		<= conv_result_end(2);
	
	det_obj_out 					<= det_obj;
	det_obj_cnt_out				<= det_obj_cnt;
	
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
		conv_result 			<= (others => '0');
		det_obj_cnt				<= (others => '0');
		
		for I in 0 to NUMBERS_OF_OBJECTS - 1 loop
			det_obj_x_pos_beg(I) 	<= (others => '0');
			det_obj_x_pos_mid(I) 	<= (others => '0');
			det_obj_x_pos_end(I) 	<= (others => '0');
			conv_result_begin(I) 	<= (others => '0');
			conv_result_end(I) 		<= (others => '0');
			det_obj(I) 					<= '0';
		end loop;

		
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
					conv_result 			<= (others => '0');
					det_obj_cnt			<= (others => '0');
					
					for I in 0 to NUMBERS_OF_OBJECTS - 1 loop
						det_obj_x_pos_beg(I) 	<= (others => '0');
						det_obj_x_pos_mid(I) 	<= (others => '0');
						det_obj_x_pos_end(I) 	<= (others => '0');
						conv_result_begin(I) 	<= (others => '0');
						conv_result_end(I) 	<= (others => '0');
						det_obj(I) 					<= '0';
					end loop;
		
					detection_state 	<= wait_for_second_pixel_state;
				end if;
			
			when wait_for_second_pixel_state => -- read the second pixel ans it's x-position
					data_in_ff_1 		<= data_in;
					data_in_ff_2		<= data_in_ff_1;
					x_pos_in_ff_1		<= x_pos_in;
					x_pos_in_ff_2		<= x_pos_in_ff_1;
					detection_state 	<= detect_start_of_line_state;
						
			when detect_start_of_line_state =>
				if (x_pos_in_ff_1 = (RES_WIDTH - 1)) OR (det_obj_cnt >= NUMBERS_OF_OBJECTS) then -- end of row is reached and check, whether maximum numbers of objects are found
					-- reset old flipflop values
					data_in_ff_1 		<= (others => '0');
					data_in_ff_2 		<= (others => '0');
					x_pos_in_ff_1 		<= (others => '0');
					x_pos_in_ff_2 		<= (others => '0');
					detection_state 	<= wait_for_first_pixel_state;
				else	-- compute the convolution (use 1st derivative)  and read the next pixel
					conv_result_var 	:= std_to_sig_resize(data_in_ff_1, 10)  -  std_to_sig_resize(data_in_ff_2, 10);-- - std_to_sig_resize(data_in_ff_2, 10) + std_to_sig_resize(data_in_ff_3, 10);
					conv_result			<=	conv_result_var;
					data_in_ff_1 		<= data_in;
					data_in_ff_2		<= data_in_ff_1;
					x_pos_in_ff_1		<= x_pos_in;
					x_pos_in_ff_2		<= x_pos_in_ff_1;
					if conv_result_var <= (- THRESHOLD) then
						if det_obj(0) = '0' then
							conv_result_begin(0)		<= abs(conv_result_var);
							det_obj_x_pos_beg(0) 	<= x_pos_in_ff_1;
						elsif det_obj(1) = '0' then
							conv_result_begin(1)		<= abs(conv_result_var);
							det_obj_x_pos_beg(1) 	<= x_pos_in_ff_1;
						elsif det_obj(2) = '0' then
							conv_result_begin(2)		<= abs(conv_result_var);
							det_obj_x_pos_beg(2) 	<= x_pos_in_ff_1;
						end if;
						detection_state	<= detect_end_of_line_state;
					end if;
				end if;
				
			when detect_end_of_line_state => 
				if x_pos_in_ff_1 = (RES_WIDTH - 1) then -- end of line is reached 
					-- reset old flipflop values
					data_in_ff_1 		<= (others => '0');
					data_in_ff_2 		<= (others => '0');
					x_pos_in_ff_1 		<= (others => '0');
					x_pos_in_ff_2 		<= (others => '0');
					detection_state 	<= wait_for_first_pixel_state;
					-- detection of the end of the line isn't possible -> clear start values of the line, which were detect in detect_begin_of_line_state_1
					if det_obj(0) = '0' then
							conv_result_begin(0)		<= (others => '0');
							det_obj_x_pos_beg(0) 	<= (others => '0');
						elsif det_obj(1) = '0' then
							conv_result_begin(1)		<= (others => '0');
							det_obj_x_pos_beg(1) 	<= (others => '0');
						elsif det_obj(2) = '0' then
							conv_result_begin(2)		<= (others => '0');
							det_obj_x_pos_beg(2) 	<= (others => '0');
					end if; 
				else	-- compute the convolution (use 1st derivative)  and read the next pixel
					conv_result_var 	:= std_to_sig_resize(data_in_ff_1, 10)  -  std_to_sig_resize(data_in_ff_2, 10);
					conv_result			<=	abs(conv_result_var);
					data_in_ff_1 		<= data_in;
					data_in_ff_2		<= data_in_ff_1;
					x_pos_in_ff_1		<= x_pos_in;
					x_pos_in_ff_2		<= x_pos_in_ff_1;
					if conv_result_var >= THRESHOLD then -- detect end of line-object
						if det_obj(0) = '0' then
							conv_result_end(0)		<= conv_result_var;
							det_obj_x_pos_end(0) 	<= x_pos_in_ff_2;
							det_obj_x_pos_mid(0) 		<= (x_pos_in_ff_2 + det_obj_x_pos_beg(0))/ 2;
							det_obj(0)					<= '1';
						elsif det_obj(1) = '0' then
							conv_result_end(1)		<= conv_result_var;
							det_obj_x_pos_end(1) 	<= x_pos_in_ff_2;
							det_obj_x_pos_mid(1)			<= (x_pos_in_ff_2 + det_obj_x_pos_beg(1))/ 2;
							det_obj(1)					<= '1';
						elsif det_obj(2) = '0' then
							conv_result_end(2)		<= conv_result_var;
							det_obj_x_pos_end(2) 	<= x_pos_in_ff_2;
							det_obj_x_pos_mid(2)		<= (x_pos_in_ff_2 + det_obj_x_pos_beg(2))/ 2;
							det_obj(2)					<= '1';
						end if; 
						det_obj_cnt	<= det_obj_cnt + 1;
						detection_state	<= detect_start_of_line_state;	
					end if;
				end if;
		end case;		
	end if;
end process;

end a;