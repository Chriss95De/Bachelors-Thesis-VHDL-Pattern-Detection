library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; 
library altera_mf;
use altera_mf.altera_mf_components.all;

entity object_position_detection is
generic(
	RES_WIDTH					: POSITIVE:= 640;	-- Resolution
	RES_HEIGHT					: POSITIVE:= 480;	-- Resolution
	ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
	ADDR_Y_WIDTH				: POSITIVE:= 9;	-- Width of the y address line
	ADDR_WIDTH					: POSITIVE:= 20;	-- Width of the address line
	DATA_BYTES_IN				: POSITIVE:= 1		-- Number of bytes input data line
	);
	
port(
	--INPUT
	clk					: in std_logic;								-- clock
	data_in				: in std_logic_vector(DATA_BYTES_IN*8-1 downto 0);		-- data for a Pixel
	data_in_valid		: in std_logic;								-- indicates valid data
	data_in_rdy			: in std_logic;								-- indicates, that data can read from one_line_read_buffer
	data_in_pos_x		: in unsigned(ADDR_X_WIDTH-1 downto 0);-- X-Coordinate of pixel/data
	data_in_pos_y		: in unsigned(ADDR_Y_WIDTH-1 downto 0);-- Y-Coordinate of pixel/data
	start_detecting	: in std_logic;								-- start obejct detecting
	-- OUTPUT request data
	rd_req_out			: out std_logic;	-- send a read-request to one_line_read_buffer
	wr_en					: out std_logic;	-- enable send bytes from one_line_read_buffer
	
	-- OUTPUT object
	object_found_out		: out std_logic;												-- indicates found object
	object_pos_x_out		: out unsigned(ADDR_X_WIDTH-1 downto 0);				-- X-Coordinate of found object
	object_pos_y_out		: out unsigned(ADDR_Y_WIDTH-1 downto 0)				-- Y-Coordinate of found object
	object_data_out		: out std_logic_vector(DATA_BYTES_IN*8-1 downto 0) -- data of found object
	);
end entity object_position_detection;

architecture a of object_position_detection is
	data_in_ff				: std_logic_vector(7 downto 0);		-- synchronized data for a Pixel
	data_in_valid_ff		: std_logic;								-- synchronized indicates valid data
	data_in_rdy_ff			: std_logic;								-- synchronized indicates, that data can read from one_line_read_buffer
	data_in_pos_x_ff		: unsigned(ADDR_X_WIDTH-1 downto 0);-- synchronized X-Coordinate of pixel/data
	data_in_pos_y_ff		: unsigned(ADDR_Y_WIDTH-1 downto 0);-- synchronized Y-Coordinate of pixel/data
	
	object_found		: std_logic;									-- indicates found object
	object_pos_x		: unsigned(ADDR_X_WIDTH-1 downto 0);	-- X-Coordinate of found object
	object_pos_y		: unsigned(ADDR_Y_WIDTH-1 downto 0);	-- Y-Coordinate of found object
	object_data			: std_logic_vector(DATA_BYTES_IN*8-1 downto 0); -- data of found object

	type object_searching_state is (WAIT_FOR_START, SEND_RED_REQ, WAIT_FOR_DATA_READY, SEARCH_OBJECT, END_SEARCHING)
	signal search_state :object_searching_state;
	
begin
	--  
	object_found_out	<= object_found;
	object_pos_x_out	<= object_pos_x;
	object_pos_y_out	<= object_pos_y;
	object_data_out	<= object_data;
	
process (reset, clk) is
	if reset = '1' then
		data_foun
	end if;
end process;
end architecture a;
	