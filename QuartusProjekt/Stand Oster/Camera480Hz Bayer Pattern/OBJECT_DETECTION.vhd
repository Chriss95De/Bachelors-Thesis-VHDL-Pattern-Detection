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
	MAX_DIFF					: POSITIVE := 20;
	RES_WIDTH				: POSITIVE := 640;		-- Resolution x
	RES_HEIGHT				: POSITIVE := 480;		-- Resolution y

	ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
	ADDR_Y_WIDTH				: POSITIVE:= 9 	-- Width of the y address line
	
	);
port (	

	clk				: in std_logic;							-- clock
	reset				: in std_logic;							-- reset
	
	det_obj_x_pos_beg		: in unsigned (ADDR_X_WIDTH-1 downto 0);
	det_obj_x_pos_end		: in unsigned (ADDR_X_WIDTH-1 downto 0);
	det_obj_found			: in std_logic;
	
	cur_pos_x				: in unsigned(ADDR_X_WIDTH-1 downto 0);
	cur_pos_y				: in unsigned(ADDR_Y_WIDTH-1 downto 0);
	
	obj_center_x			: out unsigned(ADDR_X_WIDTH-1 downto 0);
	obj_center_y			: out unsigned(ADDR_Y_WIDTH-1 downto 0);

	line_count_deb			: out unsigned(ADDR_Y_WIDTH-1 downto 0)
	 
	); 
end entity OBJECT_DETECTION;
	
	
architecture a of OBJECT_DETECTION is	
	--ffs
	signal det_obj_x_pos_beg_ff1 : unsigned (ADDR_X_WIDTH-1 downto 0);
	signal det_obj_x_pos_end_ff1 : unsigned (ADDR_X_WIDTH-1 downto 0);
	signal pxl_x_ff1 				: unsigned (ADDR_X_WIDTH-1 downto 0);
	signal pxl_y_ff1				: unsigned (ADDR_Y_WIDTH-1 downto 0);
	signal det_obj_found_ff1 	: std_logic;
	
	signal last_det_obj_x_beg	: unsigned (ADDR_X_WIDTH-1 downto 0);
	signal last_det_obj_x_end	: unsigned (ADDR_X_WIDTH-1 downto 0);
	signal last_found_y		: unsigned (ADDR_Y_WIDTH-1 downto 0);
	signal line_count 		: unsigned (ADDR_Y_WIDTH-1 downto 0);

 
begin
process (reset, clk) is
	begin
	if reset = '1' then	-- reset all values
		det_obj_x_pos_beg_ff1 <= (others => '0');
		det_obj_x_pos_end_ff1 <= (others => '0');
		pxl_x_ff1 <= (others => '0');
		pxl_y_ff1 <= (others => '0');
		obj_center_x <= (others => '0');
		obj_center_y <= (others => '0');
		last_found_y <= (others => '0');
		line_count <= (others => '0');
		
	elsif rising_edge(clk) then	
		--assing values
		det_obj_x_pos_beg_ff1 <= det_obj_x_pos_beg;
		det_obj_found_ff1 <= det_obj_found;
		pxl_x_ff1 <= cur_pos_x;
		pxl_y_ff1 <= cur_pos_y;
		
		last_det_obj_x_beg <= last_det_obj_x_beg;
		last_det_obj_x_end <= last_det_obj_x_end;
		line_count <= line_count;
		line_count_deb <= line_count;
	
		--check if new start and end in line was found
		if det_obj_found = '1' then
		
			if last_det_obj_x_beg /= 0 then --zero means no obj was found so far
			
				--check if the new line start and end fall within the previous start and end, 
				--MAX_DIFF defines how many pixel they are allowed to be appart
				if ((MAX_DIFF+last_det_obj_x_beg) >= det_obj_x_pos_beg and (last_det_obj_x_beg-MAX_DIFF) <= det_obj_x_pos_beg)
					AND
					((MAX_DIFF+last_det_obj_x_end) >= det_obj_x_pos_end and (last_det_obj_x_end-MAX_DIFF) <= det_obj_x_pos_end)
				then
					--object continues
					last_det_obj_x_beg <= det_obj_x_pos_beg;
					last_det_obj_x_end <= det_obj_x_pos_end;
				else
					--new object started
					line_count <= (others => '0');
				end if;
				
			end if;
			
			last_det_obj_x_beg <= det_obj_x_pos_beg;
			last_det_obj_x_end <= det_obj_x_pos_end;
			last_found_y <= cur_pos_y;

			if (cur_pos_y - last_found_y) >= 2 then
				line_count <= to_unsigned(1, line_count'length);
			else
				line_count <= line_count + 1;
			end if;
		end if;
		
		
		--check if object has the correct height to count as object, filter
		if line_count >= 3 then
			obj_center_x <= shift_right(last_det_obj_x_end - det_obj_x_pos_beg, 1) + det_obj_x_pos_beg;
			obj_center_y <= last_found_y - line_count;	
		else
			obj_center_x <= (others => '0');
			obj_center_y <= (others => '0');
		end if;
		
	end if;
	
end process;
end architecture a;