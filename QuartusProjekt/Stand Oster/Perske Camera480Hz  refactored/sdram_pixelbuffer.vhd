

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; 
library altera_mf;
use altera_mf.altera_mf_components.all;


entity SDRAM_PixelBuffer is
generic (
	RES_WIDTH					: POSITIVE:= 640;	-- Resolution
	RES_HEIGHT					: POSITIVE:= 480;	-- Resolution
	ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
	ADDR_Y_WIDTH				: POSITIVE:= 9 	-- Width of the y address line
	);
port (

	reset							: in std_logic;							-- Async reset
	clk							: in std_logic;
	
	-- ReadBuffer control signals
	buf_data_req				: out std_logic;							-- If data_act is not set, request frame data from Read Buffer
	buf_data_ena				: out std_logic;							-- If data_rdy is set, read out the next data byte
	buf_data_act				: in std_logic;							-- Read Buffer is busy reading out data
	buf_data_rdy				: in std_logic;							-- Read Buffer has buffered enough data
	buf_data						: in std_logic_vector(7 downto 0);		-- Read out data
	buf_data_val				: in std_logic;							-- data is valid
	
	-- request frame data
	buf_frame_x					: out unsigned(ADDR_X_WIDTH-1 downto 0);
	buf_frame_w					: out unsigned(ADDR_X_WIDTH-1 downto 0);
	buf_frame_y					: out unsigned(ADDR_Y_WIDTH-1 downto 0);
	buf_frame_h					: out unsigned(ADDR_Y_WIDTH-1 downto 0);
	
	
	-- Output data
	pxl_data_req				: in std_logic;							-- If data_act is not set, request frame data from Pixel Buffer
	pxl_data_ena				: in std_logic;							-- If data_rdy is set, read out the next data byte
	pxl_data_act				: out std_logic;							-- Pixel Buffer is busy reading out data
	pxl_data_l1					: out std_logic_vector(5 * 8 - 1 downto 0);	-- Pixel data line 1 *** First pixel at 7..0, Highest pixel at 39..32
	pxl_data_l2					: out std_logic_vector(5 * 8 - 1 downto 0);	-- Pixel data line 2
	pxl_data_l3					: out std_logic_vector(5 * 8 - 1 downto 0);	-- Pixel data line 3
	pxl_data_l4					: out std_logic_vector(5 * 8 - 1 downto 0);	-- Pixel data line 4
	pxl_data_l5					: out std_logic_vector(5 * 8 - 1 downto 0);	-- Pixel data line 5
	pxl_data_val				: out std_logic;							-- data is valid
	
	-- current center position
	pxl_center_x				: out unsigned(ADDR_X_WIDTH-1 downto 0);
	pxl_center_y				: out unsigned(ADDR_Y_WIDTH-1 downto 0);	
	
	-- request frame data
	-- Position of the first pixel of the 5x5 square
	pxl_frame_x					: in unsigned(ADDR_X_WIDTH-1 downto 0);
	pxl_frame_w					: in unsigned(ADDR_X_WIDTH-1 downto 0);
	pxl_frame_y					: in unsigned(ADDR_Y_WIDTH-1 downto 0);
	pxl_frame_h					: in unsigned(ADDR_Y_WIDTH-1 downto 0);
	
	-- Debugging signals
	dbg_state					: out unsigned(7 downto 0); 						-- Current state
	dbg_err_code				: out std_logic_vector(15 downto 0)	 	-- Some debug information
	
	);
end entity SDRAM_PixelBuffer;
	
	
architecture a of SDRAM_PixelBuffer is


	
	-- *********************
	-- Output shift register
	-- *********************
	
	-- First (Oldest) pixel at shift_lX(0), Highest (Latest) pixel at shift_lX(4)
	
	-- Function:
	--                 Output data:
	--                 ____________________________________________________________________________
	--                |                                                                            |
	-- new_data(0) -> | -> shift_l1(4) -> shift_l1(3) -> shift_l1(2) -> shift_l1(1) -> shift_l1(0) |
	-- new_data(1) -> | -> shift_l2(4) -> shift_l2(3) -> shift_l2(2) -> shift_l2(1) -> shift_l2(0) |
	-- new_data(2) -> | -> shift_l3(4) -> shift_l3(3) -> shift_l3(2) -> shift_l3(1) -> shift_l3(0) |
	-- new_data(3) -> | -> shift_l4(4) -> shift_l4(3) -> shift_l4(2) -> shift_l4(1) -> shift_l4(0) |
	-- new_data(4) -> | -> shift_l5(4) -> shift_l5(3) -> shift_l5(2) -> shift_l5(1) -> shift_l5(0) |
	--                |____________________________________________________________________________|

	
	type t_shift_data is array (0 to 4) of std_logic_vector(7 downto 0);
	signal shift_l1			: t_shift_data;
	signal shift_l2			: t_shift_data;
	signal shift_l3			: t_shift_data;
	signal shift_l4			: t_shift_data;
	signal shift_l5			: t_shift_data;
	

	-- ****************
	-- FIFO Buffer data
	-- ****************
	
	subtype t_active_buffer is integer range 0 to 2;
	constant BUFFER_NONE : t_active_buffer := 0;
	constant BUFFER_A : t_active_buffer := 1;
	constant BUFFER_B : t_active_buffer := 2;
	
	component scfifo
   generic (
      ALLOW_RWCYCLE_WHEN_FULL:	STRING;
      ALMOST_EMPTY_VALUE: 			POSITIVE;		
      ALMOST_FULL_VALUE: 			POSITIVE;
      LPM_NUMWORDS: 					POSITIVE;		
      LPM_SHOWAHEAD: 				STRING;
		LPM_WIDTH: 						POSITIVE;
      OVERFLOW_CHECKING: 			STRING;
      UNDERFLOW_CHECKING:			STRING;
      USE_EAB: 						STRING
		);
   port (
		data: 											in STD_LOGIC_VECTOR(LPM_WIDTH-1 downto 0);
      clock, wrreq, rdreq, sclr, aclr: 		in STD_LOGIC;
      full,almost_full, empty, almost_empty: out STD_LOGIC;
      q: 												out STD_LOGIC_VECTOR(LPM_WIDTH-1 downto 0);
      usedw: 											out STD_LOGIC_VECTOR(POSITIVE(CEIL(LOG2(REAL(LPM_NUMWORDS))))-1 downto 0)
		);
	end component;
	
	-- FIFO buffer signals
		
	type t_buffer_data is array (0 to 3) of std_logic_vector(7 downto 0);
	
	signal buffer_data_A		: t_buffer_data; 	
	signal buffer_data_B		: t_buffer_data; 											-- Data to buffer
	signal buffer_wrreq_A	: std_logic_vector(3 downto 0);	-- write request
	signal buffer_wrreq_B	: std_logic_vector(3 downto 0);	-- write request
	signal buffer_rdreq_A	: std_logic_vector(3 downto 0);	-- read request
	signal buffer_rdreq_B	: std_logic_vector(3 downto 0);	-- read request
	signal buffer_aclr_A		: std_logic_vector(3 downto 0);	-- async clear
	signal buffer_aclr_B		: std_logic_vector(3 downto 0);	-- async clear
	signal buffer_q_A			: t_buffer_data;
	signal buffer_q_B			: t_buffer_data;
	
	-- Byte buffer to read data from FIFO before use
	-- to avoid 1clk latency when reading data from FIFO
	
	-- Function: 
	--
	-- i:init     Has to be called once before read or noread
	-- r:read     Read out the next byte, either from buf or from q
	-- n:noread   On first call, save data on buf, on further call, do nothing
	--
	-- Start with noread
	--
	--            i...n...n...n...r...r...r...n...n...n
	--      clk   0   1   2   3   4   5   6   7   8   9
	--      buf        -> b0  b0  b0           -> b3  b3
	--   fifo_q   b0  b0  b1  b1  b1  b1  b2  b3  b4  b4
	-- fifo_ack   1   0   0   0   1   1   1   0   0   0
	--   output                   b0  b1  b2
	--
	-- Start with read
	--
	--            i...r...r...r...n...n...r...n...r...r
	--      clk   0   1   2   3   4   5   6   7   8   9
	--      buf                    -> b3  b3   -> b4
	--   fifo_q   b0  b0  b1  b2  b3  b4  b4  b4  b5  b5
	-- fifo_ack   1   1   1   1   0   0   1   0   1   1
	--   output       b0  b1  b2          b3      b4  b5
	
	signal fifo_read_buffer_A				: t_buffer_data;
	signal fifo_read_buffer_B				: t_buffer_data;
	signal fifo_read_buffer_A_filled		: std_logic;	
	signal fifo_read_buffer_B_filled		: std_logic;
	
	procedure fifo_init_read(sel_buffer : in t_active_buffer) is
	begin
		if sel_buffer = BUFFER_A then
			buffer_rdreq_A <= (others => '1');
			fifo_read_buffer_A_filled <= '0';
			for I in 0 to 3 loop	
				fifo_read_buffer_A(I) <= (others => '0');
			end loop;
		elsif sel_buffer = BUFFER_B then
			buffer_rdreq_B <= (others => '1');
			fifo_read_buffer_B_filled <= '0';
			for I in 0 to 3 loop	
				fifo_read_buffer_B(I) <= (others => '0');
			end loop;
		end if;
	end procedure fifo_init_read;
	
	procedure fifo_read(variable data : out t_buffer_data; sel_buffer : in t_active_buffer) is
	begin	
		if sel_buffer = BUFFER_A then
			buffer_rdreq_A <= (others => '1');
			if fifo_read_buffer_A_filled = '0' then
				data := buffer_q_A;
			else
				fifo_read_buffer_A_filled <= '0';
				data := fifo_read_buffer_A;
			end if;
		elsif sel_buffer = BUFFER_B then
			buffer_rdreq_B <= (others => '1');
			if fifo_read_buffer_B_filled = '0' then
				data := buffer_q_B;
			else
				fifo_read_buffer_B_filled <= '0';
				data := fifo_read_buffer_B;
			end if;
		end if;	
	end procedure fifo_read;
				
	procedure fifo_noread(sel_buffer : in t_active_buffer) is
	begin
		if sel_buffer = BUFFER_A then
			buffer_rdreq_A <= (others => '0');
			if fifo_read_buffer_A_filled = '0' then
				fifo_read_buffer_A_filled <= '1';
				fifo_read_buffer_A <= buffer_q_A;
			end if;
		elsif sel_buffer = BUFFER_B then
			buffer_rdreq_B <= (others => '0');
			if fifo_read_buffer_B_filled = '0' then
				fifo_read_buffer_B_filled <= '1';
				fifo_read_buffer_B <= buffer_q_B;
			end if;
		end if;	
	end procedure fifo_noread;

	
	-- *************
	-- State machine
	-- *************
	
	type t_state is (ST_WAITREQ, ST_INIT_REQ, ST_INIT_WAITREADBUF, ST_INIT_FILLBUF_N, ST_WAITREADBUF, ST_FILLOUTPUT, ST_WAIT_ENA, ST_OUTPUT_LINE);
	signal state				: t_state;	
	signal active_buffer 	: t_active_buffer;
	signal pxl_ena_ff			: std_logic; 	-- to detect edge
	signal pxl_req_ff			: std_logic; 	-- to detect edge
	signal i						: integer; 	-- Counter for initialization
	signal req_n				: integer; 	-- Counter for initialization
	signal rcv_n				: integer; 	-- Counter for initialization
	
	signal pxl_center_x_ff			: unsigned(ADDR_X_WIDTH-1 downto 0);
	signal pxl_center_y_ff			: unsigned(ADDR_Y_WIDTH-1 downto 0);	
	
	
	-- ****************
	-- Helper functions
	-- ****************
	
	-- Shift the output registers by one pixel and insert new_data
	procedure shift_output(new_data : in t_shift_data) is
	begin
		for I in 0 to 3 loop	
			shift_l1(I) <= shift_l1(I+1);
			shift_l2(I) <= shift_l2(I+1);
			shift_l3(I) <= shift_l3(I+1);
			shift_l4(I) <= shift_l4(I+1);
			shift_l5(I) <= shift_l5(I+1);
		end loop;		
		shift_l1(4) <= new_data(0);
		shift_l2(4) <= new_data(1);
		shift_l3(4) <= new_data(2);
		shift_l4(4) <= new_data(3);
		shift_l5(4) <= new_data(4);
	end shift_output;	
	
	-- Reset the output shift register
	procedure reset_output(dummy : in std_logic) is
	begin
		for I in 0 to 4 loop	
			shift_l1(I) <= (others => '1');
			shift_l2(I) <= (others => '1');
			shift_l3(I) <= (others => '1');
			shift_l4(I) <= (others => '1');
			shift_l5(I) <= (others => '1');
		end loop;
	end reset_output;
	
	-- Output the next five pixel read from the active line buffer
	procedure output(sel_buffer : in t_active_buffer) is
		variable shift_data_tmp : t_shift_data;
		variable fifo_data_tmp : t_buffer_data;
	begin
		-- Read data from FIFO
		fifo_read(fifo_data_tmp, sel_buffer);
		-- Create output data from active Buffer
		shift_data_tmp(0) := fifo_data_tmp(0); -- Line 0
		shift_data_tmp(1) := fifo_data_tmp(1);
		shift_data_tmp(2) := fifo_data_tmp(2);
		shift_data_tmp(3) := fifo_data_tmp(3);
		shift_data_tmp(4) := buf_data;
		
		if sel_buffer = BUFFER_A then			
			-- Save data in opposite Buffer shifted by one line			
			buffer_data_B(0) <= shift_data_tmp(1);	-- Line 1 gets new line 0 
			buffer_data_B(1) <= shift_data_tmp(2);	
			buffer_data_B(2) <= shift_data_tmp(3);	
			buffer_data_B(3) <= shift_data_tmp(4);
			buffer_wrreq_B(0) <= '1';
			buffer_wrreq_B(1) <= '1';
			buffer_wrreq_B(2) <= '1';
			buffer_wrreq_B(3) <= '1';
		elsif sel_buffer = BUFFER_B then			
			-- Save data in opposite Buffer shifted by one line			
			buffer_data_A(0) <= shift_data_tmp(1);	-- Line 1 gets new line 0 
			buffer_data_A(1) <= shift_data_tmp(2);	
			buffer_data_A(2) <= shift_data_tmp(3);	
			buffer_data_A(3) <= shift_data_tmp(4);
			buffer_wrreq_A(0) <= '1';
			buffer_wrreq_A(1) <= '1';
			buffer_wrreq_A(2) <= '1';
			buffer_wrreq_A(3) <= '1';
		end if;
		
		-- Output next pixel
		shift_output(shift_data_tmp);
	end output;
	
begin


-- ***********
-- FIFO Buffer
-- ***********

-- Important: FIFO are in SHOWAHEAD mode, rdreq acts like a rdack

scfifo_gen: for I in 0 to 3 generate	

	scfifo_buffer_a: scfifo
	generic map (	
		LPM_NUMWORDS			=> 1024,
		LPM_SHOWAHEAD			=> "ON",
		LPM_WIDTH				=> 8,
		OVERFLOW_CHECKING		=> "OFF",
		UNDERFLOW_CHECKING	=> "ON",
		USE_EAB					=> "ON",
		ALMOST_EMPTY_VALUE	=> 16,
		ALMOST_FULL_VALUE		=> 1008,
		ALLOW_RWCYCLE_WHEN_FULL	=> "OFF"
	)
	port map (
		data						=> buffer_data_A(I),
		clock						=> clk,
		wrreq						=> buffer_wrreq_A(I),
		rdreq						=> buffer_rdreq_A(I),
		aclr						=> buffer_aclr_A(I),
		sclr						=> '0',
		q							=> buffer_q_A(I)
	);
	
	scfifo_buffer_b: scfifo
	generic map (	
		LPM_NUMWORDS			=> 1024,
		LPM_SHOWAHEAD			=> "ON",
		LPM_WIDTH				=> 8,
		OVERFLOW_CHECKING		=> "OFF",
		UNDERFLOW_CHECKING	=> "ON",
		USE_EAB					=> "ON",
		ALMOST_EMPTY_VALUE	=> 16,
		ALMOST_FULL_VALUE		=> 1008,
		ALLOW_RWCYCLE_WHEN_FULL	=> "OFF"
	)
	port map (
		data						=> buffer_data_B(I),
		clock						=> clk,
		wrreq						=> buffer_wrreq_B(I),
		rdreq						=> buffer_rdreq_B(I),
		aclr						=> buffer_aclr_B(I),
		sclr						=> '0',
		q							=> buffer_q_B(I)
	);

end generate scfifo_gen;





-- ***********
-- Output data
-- ***********

output_data: for I in 0 to 4 generate	
	pxl_data_l1(I*8+7 downto I*8) <= shift_l1(I);
	pxl_data_l2(I*8+7 downto I*8) <= shift_l2(I);
	pxl_data_l3(I*8+7 downto I*8) <= shift_l3(I);
	pxl_data_l4(I*8+7 downto I*8) <= shift_l4(I);
	pxl_data_l5(I*8+7 downto I*8) <= shift_l5(I);
end generate output_data;

pxl_center_x <= pxl_center_x_ff;
pxl_center_y <= pxl_center_y_ff;



-- *********************
-- State machine process
-- *********************

process(clk, reset) is

	variable line_end_tmp : std_logic;
	variable frame_end_tmp : std_logic;

begin

	if reset = '1' then
	
		-- Async Reset
	
		buf_data_req 	<= '0';
		buf_data_ena 	<= '0';
		pxl_data_act 	<= '0';
		pxl_data_val 	<= '0';		
		state 			<= ST_WAITREQ;		
		active_buffer 	<= BUFFER_NONE;
		pxl_ena_ff 		<= '0';
		pxl_req_ff 		<= '0';	
		i					<= 0;	
		req_n				<= 0;	
		rcv_n				<= 0;	
		
		dbg_state 		<= (others => '1');
		dbg_err_code 	<= (others => '1');
		
		for I in 0 to 3 loop			
			buffer_wrreq_A(I) 	<= '0';
			buffer_rdreq_A(I) 	<= '0';
			buffer_aclr_A(I) 		<= '1';		
			buffer_data_A(I) 		<= (others => '0');
			buffer_wrreq_B(I) 	<= '0';
			buffer_rdreq_B(I) 	<= '0';
			buffer_aclr_B(I) 		<= '1';		
			buffer_data_B(I) 		<= (others => '0');
		end loop;	
		
		pxl_center_x_ff	<= (others => '0');
		pxl_center_y_ff	<= (others => '0');			
		
		buf_frame_x	<= (others => '0');
		buf_frame_w	<= (others => '0');
		buf_frame_y	<= (others => '0');
		buf_frame_h	<= (others => '0');
		
		reset_output('0');
		
	elsif rising_edge(clk) then
	
		-- Clock sync
	
		dbg_state <= to_unsigned(0,8);
	
	
dbg_err_code(7 downto 0) <= shift_l3(2);
dbg_err_code(15 downto 8) <= buf_data;
	
	
	
		-- Detect Rising edges on data_req and data_ena
		pxl_req_ff <= pxl_data_req;
		pxl_ena_ff <= pxl_data_ena;		
	
		-- Preset values
		pxl_data_act <= '0';	
		--buf_frame_x <= (others => '0');
		--buf_frame_y <= (others => '0');
		--buf_frame_w <= (others => '0');
		--buf_frame_h <= (others => '0');
		buf_data_req <= '0';
		buf_data_ena <= '0';
		pxl_data_val 	<= '0';	
		for I in 0 to 3 loop			
			buffer_wrreq_A(I) 	<= '0';
			buffer_rdreq_A(I) 	<= '0';
			buffer_aclr_A(I) 		<= '0';		
			buffer_data_A(I) 		<= (others => '0');
			buffer_wrreq_B(I) 	<= '0';
			buffer_rdreq_B(I) 	<= '0';
			buffer_aclr_B(I) 		<= '0';		
			buffer_data_B(I) 		<= (others => '0');
		end loop;

		
		-- State machine
		
		case state is
		
		
		
		-- Wait for frame request signal
		when ST_WAITREQ =>
			dbg_state <= to_unsigned(1,8);
			
			
			-- Rising edge on data_req
			if pxl_data_req = '1' and pxl_req_ff = '0' then				
				-- Set Pixel Buffer to busy
				pxl_data_act <= '1';				
				-- Wait for the Read Buffer to be active
				state <= ST_INIT_REQ;				
			end if;
			
			
			
		
		-- Initialize: Wait for the Read Buffer to be active
		when ST_INIT_REQ =>
			dbg_state <= to_unsigned(2,8);
			
			-- Set Pixel Buffer to busy
			pxl_data_act <= '1';
			
			-- Request next frame from Read Buffer
			buf_frame_x <= pxl_frame_x;
			buf_frame_y <= pxl_frame_y;
			buf_frame_w <= pxl_frame_w + 4; -- 5x5px square -> load five px more
			buf_frame_h <= pxl_frame_h + 4; -- 5x5px square -> load five px more
			buf_data_req <= '1';
			
			-- Reset position
			pxl_center_x_ff <= pxl_frame_x;
			pxl_center_y_ff <= pxl_frame_y;
			
			-- Check if Read Buffer is active
			if buf_data_act = '1' then
				-- Set counter for initialization to zero
				i <= 0;			
				-- Start with Buffer A
				active_buffer <= BUFFER_A;
				-- Wait for the Read Buffer to be ready
				state <= ST_INIT_WAITREADBUF;
			end if;
			
			
			
		-- Initialize: Wait for Read Buffer to be ready (4x)
		when ST_INIT_WAITREADBUF =>
			dbg_state <= to_unsigned(3,8);
			
			-- Set Pixel Buffer to busy
			pxl_data_act <= '1';
			
			-- Wait for Read buffer to be ready
			if buf_data_rdy = '1' then
				-- Start reading data
				buf_data_ena <= '1';
				-- Wait for data to be valid
				-- Read next line
				state <= ST_INIT_FILLBUF_N;				
			end if;
			
			
		
		-- Initialize: Fill Buffer N (4x)
		when ST_INIT_FILLBUF_N =>
			dbg_state <= to_unsigned(4,8);
			
			-- Set Pixel Buffer to busy
			pxl_data_act <= '1';	
	
			-- Receive next pixel
			if buf_data_val = '1' then
				-- Read out next pixel
				buffer_data_A(i) <= buf_data;
				buffer_wrreq_A(i) <= '1';
			end if;	
			
			-- Read until end of line (no more data ready)
			if buf_data_rdy = '0' and buf_data_val = '0' then
				-- Ckeck if 4 lines have been read
				if i >= 3 then
					-- Buffer initilization finished
					i <= 0;
					-- Start outputting data when Read Buffer is ready
					state <= ST_WAITREADBUF;
				else 
					-- Initialize next line
					i <= i+1;
					-- Wait for the Read Buffer to be ready
					state <= ST_INIT_WAITREADBUF;
				end if;
			else			
				-- Request next pixel
				buf_data_ena <= '1';
			end if;
			
			
		
		-- Wait for Read Buffer to be ready
		when ST_WAITREADBUF =>
			dbg_state <= to_unsigned(5,8);
						
			-- Set Pixel Buffer to busy
			pxl_data_act <= '1';
			
			-- Wait for Read buffer to be ready
			if buf_data_rdy = '1' then
				-- Start reading data
				req_n <= 1;
				rcv_n <= 0;
				buf_data_ena <= '1';
				-- Clear output				
				reset_output('0');
				-- Prepare reading from FIFO
				fifo_init_read(active_buffer);
				-- Fill output shift register
				state <= ST_FILLOUTPUT;				
			end if;
			
			
		
		-- Fill the output shift register with the first 4 pixel
		when ST_FILLOUTPUT =>
			dbg_state <= to_unsigned(6,8);
						
			-- Set Pixel Buffer to busy
			pxl_data_act <= '1';
			
			-- Receive pixel
			if buf_data_val = '1' then
				-- Output next pixel
				output(active_buffer); -- calls fifo_read(active_buffer)
				rcv_n <= rcv_n+1;
			else
				-- No read operation on FIFO
				fifo_noread(active_buffer);
			end if;
			

			
			-- Request 4 pixel
			if req_n < 4 then
				buf_data_ena <= '1';
				req_n <= req_n+1;
			end if;	
			
			-- 4 Pixel received
			if req_n >= 4 and rcv_n >= 4 then
				-- Output buffer filled
				-- Wait for enable data output
				state <= ST_WAIT_ENA;	
				i <= 0;			
			end if;
				
			
		
		-- Wait for ena signal to start output the data
		when ST_WAIT_ENA =>
			dbg_state <= to_unsigned(7,8);
						
			-- Set Pixel Buffer to busy
			pxl_data_act <= '1';
			
			-- Check for output enable rising edge
			if pxl_data_ena = '1' and pxl_ena_ff = '0' then
				-- Output data
				buf_data_ena <= '1';
				-- Prepare reading from FIFO
				fifo_noread(active_buffer);
				
				state <= ST_OUTPUT_LINE;				
			end if;
			
			
		
		-- Output the data for the line
		when ST_OUTPUT_LINE =>
			dbg_state <= to_unsigned(8,8);	
						
			-- Set Pixel Buffer to busy
			pxl_data_act <= '1';
					
			-- Receive next pixel
			if buf_data_val = '1' then
				-- Output next pixel
				output(active_buffer); -- calls fifo_read(active_buffer)
				pxl_data_val <= '1';
				pxl_center_x_ff <= pxl_center_x_ff + 1;
			else
				-- No read operation on FIFO
				fifo_noread(active_buffer);
			end if;		
				
			
			
			-- Increase position
			line_end_tmp := '0';
			frame_end_tmp := '0';
			-- if (pxl_center_x_ff - pxl_frame_x + 1) >= pxl_frame_w then
			if buf_data_rdy = '0' and buf_data_val = '0' then
				line_end_tmp := '1';
				pxl_center_x_ff <= (others => '0');
				pxl_center_y_ff <= pxl_center_y_ff + 1;
				--if (pxl_center_y_ff - pxl_frame_y + 1) >= pxl_frame_h then
				if buf_data_act = '0' then
					pxl_center_y_ff <= (others => '0');
					frame_end_tmp := '1';					
				end if;
			end if;
			
			-- Check if line or frame ended
			if frame_end_tmp = '1' then
				-- Clear buffer
				for I in 0 to 3 loop
					buffer_aclr_A(I) 		<= '1';
					buffer_aclr_B(I) 		<= '1';
					-- Clear output				
					reset_output('0');
				end loop;	
				active_buffer <= BUFFER_NONE;
				-- Wait for next request
				state <= ST_WAITREQ;
			elsif line_end_tmp = '1' then
				-- Change Buffer A and B
				if active_buffer = BUFFER_A then
					active_buffer <= BUFFER_B;
					buffer_aclr_A(I) 		<= '1';
				else
					active_buffer <= BUFFER_A;
					buffer_aclr_B(I) 		<= '1';
				end if;
				-- Clear output				
				reset_output('0');
				-- Initialize next line
				state <= ST_WAITREADBUF;
			elsif pxl_data_ena = '0' then
				-- Wait for enable data output
				state <= ST_WAIT_ENA;	
			else
				-- Stay in state and request next pixel from Read Buffer				
				buf_data_ena <= '1';
			end if;
		
		
			
		end case; -- state
	
	end if; 
	
end process;

end architecture a;