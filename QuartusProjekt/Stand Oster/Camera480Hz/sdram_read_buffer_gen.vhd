
-- *** Simplified buffer overview ***
--
--                     Buffer A  Buffer B
--                       _____    _____
--                      |FIFO |  |FIFO |
--                      |_____|  |_____|
--                      in| |out in| |out
--             mux ___    | |      | |    ___ demux
--                /   |___| |______|_|___|   \
--  SDRAM data --|    |____________| |___|    |-- VGA data
--                \___|      __          |___/
--             _____|_______| 1|.__________|
--                          |__|
--
--
--  *** Sync timing ***
--
--                             
--                 _                ___
--  out_line_sync   |______________|   |__
--                  :              :
--                  :              :    out_frame_sync  
--                  :______________:... _| 
--                  | frame        |   |
--                  |              |   |
--                  |              |   |
--                  |              |   |
--                  |______________|...|_ start reading first line of next frame (RD_WAITFRAME_STATE -> RD_REQ_STATE)
--                                       |
--                                      _|
--                                     |
--
--
--  *** data_valid Handshake ***
--  
--      1) sdram state machine sets bufferX_valid
--      2) vga state machine synchronizes valid signal and starts rendering the line
--      3) after finishing the line, the vga state machine request a reset of the valid signal
--      4) the vga state machine waits for the out_bufferX_valid signal to get 0
--      5) the reset is synchronized in the sdram state machine
--
--                                            bufferX_valid
--                                                 ___     ___     ___
--                   bufferX_reset              --|S  |---|  d|---|  d|-- bufferX_valid_ff2
--                        ___     ___     ___   .-|>  |   |   |   |   |
--                     --|  d|---|  d|---|  d|----|R__| .-|>__| .-|>__|
--                       |   |   |   |   |   |  |       |       |
--                     .-|>__| .-|>__| .-|>__|  |       |       |
--                     |       |       |        |       |       |
--          sdram_clk ---------.-------.--------.       |       |
--                     |                                |       |
--      out_pixel_clk -.--------------------------------.-------.
--
--


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; 
library altera_mf;
use altera_mf.altera_mf_components.all;


entity SDRAM_Read_Buffer_gen is
generic (
	LINE_BUFFER_N				: POSITIVE:= 4;	-- Number of lines buffered
	RES_WIDTH					: POSITIVE:= 640;	-- Resolution
	RES_HEIGHT					: POSITIVE:= 480;	-- Resolution
	ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
	ADDR_Y_WIDTH				: POSITIVE:= 9;	-- Width of the y address line
	ADDR_WIDTH					: POSITIVE:= 20;	-- Width of the address line
	DATA_BYTES_IN				: POSITIVE:= 4	-- Number of bytes input data line
	);
port (

	-- SDRAM signals
	sdram_clk					: in std_logic;							-- SDRAM Clock
	sdram_data					: in std_logic_vector(DATA_BYTES_IN*8-1 downto 0);	-- data from SDRAM
	sdram_data_valid			: in std_logic;							-- Indicates valid data from SDRAM
	sdram_wait					: in std_logic;							-- SDRAM is busy	
	sdram_addr					: out std_logic_vector(ADDR_WIDTH-1 downto 0);			-- Current memory position to read
	sdram_rd						: out std_logic;							-- SDRAM read command
	
	-- SDRAM control signals
	rd_en							: in std_logic;							-- If read is not active, the next line is only read if rd_en is true 
	rd_active					: out std_logic;							-- true while the buffer is reading from the SDRAM
	rd_req						: out std_logic;							-- true until rd_en is set
	
	-- VGA signals
	out_pixel_clk				: in std_logic;							-- VGA pixel Clock
	out_line_sync				: in std_logic;							-- Low active, falling edge when display time ends, rising edge when next line starts
	out_frame_sync				: in std_logic;							-- Low active, falling edge when display time ends, rising edge when next frame starts
	out_disp_ena				: in std_logic;							-- Display enable signal
	out_data						: out std_logic_vector(7 downto 0);	-- Current output data	
	out_data_valid				: out std_logic;							-- Current output data is valid
	
	-- Other signals
	reset							: in std_logic;							-- Async reset
	
	
	-- Debugging signals
	dbg_rd_state				: out unsigned(7 downto 0); 				-- Current rd_state
	dbg_wr_state				: out unsigned(7 downto 0); 				-- Current wr_state
	dbg_err_code				: out std_logic_vector(15 downto 0);	 	-- Some debug information
	dbg_rcv						: out unsigned(15 downto 0); 
	dbg_req						: out unsigned(15 downto 0)
	
	);
end entity SDRAM_Read_Buffer_gen;
	
	
architecture a of SDRAM_Read_Buffer_gen is


	-- ****************
	-- FIFO Buffer data
	-- ****************
	
	subtype t_active_buffer is integer range 0 to LINE_BUFFER_N;
	constant BUFFER_NONE : t_active_buffer := LINE_BUFFER_N;
		
	component dcfifo
   generic (
      DELAY_RDUSEDW:			POSITIVE;
      DELAY_WRUSEDW: 		POSITIVE;		
      LPM_NUMWORDS: 			POSITIVE;
      LPM_SHOWAHEAD: 		STRING;
		LPM_WIDTH: 				POSITIVE;
      OVERFLOW_CHECKING: 	STRING;
      RDSYNC_DELAYPIPE: 	POSITIVE;
      UNDERFLOW_CHECKING:	STRING;
      USE_EAB: 				STRING;
      WRSYNC_DELAYPIPE: 	POSITIVE
		);
   port (
		data: 										in STD_LOGIC_VECTOR(LPM_WIDTH-1 downto 0);
      rdclk, wrclk, wrreq, rdreq, aclr: 	in STD_LOGIC;
      rdfull,wrfull, wrempty, rdempty: 	out STD_LOGIC;
      q: 											out STD_LOGIC_VECTOR(LPM_WIDTH-1 downto 0);
      rdusedw, wrusedw: 						out STD_LOGIC_VECTOR(POSITIVE(CEIL(LOG2(REAL(LPM_NUMWORDS))))-1 downto 0)
		);
	end component;
	
	-- FIFO buffer signals
		
	type t_buffer_data is array (0 to LINE_BUFFER_N-1) of std_logic_vector(DATA_BYTES_IN*8-1 downto 0);
	signal buffer_data		: t_buffer_data; 											-- Data to buffer
	signal buffer_wrreq		: std_logic_vector(LINE_BUFFER_N-1 downto 0);	-- write request
	signal buffer_rdreq		: std_logic_vector(LINE_BUFFER_N-1 downto 0);	-- read request
	signal buffer_aclr		: std_logic_vector(LINE_BUFFER_N-1 downto 0);	-- async clear
	signal buffer_wrempty	: std_logic_vector(LINE_BUFFER_N-1 downto 0);	-- write state machine empty signal
	signal buffer_rdempty	: std_logic_vector(LINE_BUFFER_N-1 downto 0);	-- read state machine empty signal
	signal buffer_q			: t_buffer_data;											-- Data from buffer

	-- buffer valid handshake signals
	
	signal buffer_valid		: std_logic_vector(LINE_BUFFER_N-1 downto 0);		-- Synchronized with cam_clk
																										-- Buffer n is filled with valid data for the next line
	signal buffer_valid_ff1	: std_logic_vector(LINE_BUFFER_N-1 downto 0);		-- Synchronized with sdram_clk
	signal buffer_valid_ff2	: std_logic_vector(LINE_BUFFER_N-1 downto 0);		-- Synchronized with sdram_clk	
	signal buffer_reset		: std_logic_vector(LINE_BUFFER_N-1 downto 0);		-- Synchronized with sdram_clk
	signal buffer_reset_ff1	: std_logic_vector(LINE_BUFFER_N-1 downto 0);		-- Synchronized with cam_clk
	signal buffer_reset_ff2	: std_logic_vector(LINE_BUFFER_N-1 downto 0);		-- Synchronized with cam_clk
	
	


	
	-- signals for the read data state machine
	
	type rd_state_type is (RD_WAITFRAME_STATE, RD_REQ_STATE, RD_DATA_STATE, RD_REC_WAITREQUEST_STATE_1, RD_REC_WAITREQUEST_STATE_2, RD_WAITREQUEST_STATE, RD_WAITBUFFER_STATE);
	signal rd_state				: rd_state_type;
	
	signal rd_active_buffer 	: t_active_buffer;
	
	signal sdram_rd_req_n		: unsigned(15 downto 0); -- Because of the delay between read request and data valid,
	signal sdram_rd_rcv_n		: unsigned(15 downto 0); -- the number of reveived words is compared to the number of read requests
	
	
	-- Component to resolve coordinates to memory address
	component xy_to_address is
	generic (
		ADDR_WIDTH		: positive;
		RES_WIDTH		: positive;
		RES_HEIGHT		: positive;
		ADDR_X_WIDTH	: POSITIVE;
		ADDR_Y_WIDTH	: POSITIVE;
		DATA_BYTES		: POSITIVE
	);
	port  
	(
		X         : in unsigned(ADDR_X_WIDTH-1 DOWNTO 0);
		Y         : in unsigned(ADDR_Y_WIDTH-1 DOWNTO 0);
		ADDR      : out std_logic_vector(ADDR_WIDTH-1 DOWNTO 0)
	);
	end component xy_to_address;
	

	
	-- Connected to xy_to_address, to calculate memory address
	signal rd_next_addr_x		: unsigned(ADDR_X_WIDTH-1 downto 0);
	signal rd_next_addr_y		: unsigned(ADDR_Y_WIDTH-1 downto 0);
	signal rd_next_addr			: std_logic_vector(ADDR_WIDTH-1 downto 0);
	
	signal out_frame_sync_ff	: std_logic;
	
	
	
	
	
	-- siganls for the write data state machine
	
	type wr_state_type is (WR_WAITBUFFER_STATE, WR_BUF_REQ_DATA_1,WR_BUF_REQ_DATA_2,WR_BUF_DATA_1,WR_BUF_DATA_2, WR_BUF_FIFO_DATA, WR_WAIT_ENA, WR_DATA_STATE, WR_WAITRESET_STATE);
	signal wr_state				: wr_state_type;
	
	signal wr_active_buffer 	: t_active_buffer;
	signal wr_next_buffer 		: t_active_buffer;	
	
	signal out_line_sync_ff		: std_logic; 	-- to detect falling edge
	signal out_disp_ena_ff		: std_logic; 	-- to detect falling edge
	
	signal output_byte_n			: integer;	
	
	signal out_data_ff			: std_logic_vector(7 downto 0);	-- Current output data
	
	
	-- Buffer to read whole line from the FIFO
	constant WR_LINE_BUFFER_SIZE : integer := 8;
	type t_wr_line_buffer is array (0 to 7) of std_logic_vector(7 downto 0);
	signal wr_line_buffer	: t_wr_line_buffer;	
	signal wr_line_buffer_pos	: integer; 	-- Next byte position on the line buffer
	signal wr_line_buffer_req	: integer; 	-- Requested words from the FIFO
	signal wr_line_buffer_rec	: integer; 	-- Received words from the FIFO
	signal wr_line_buffer_cnt	: integer; 	-- Received words from the FIFO
	
	
	-- Debug Signal
	
	signal dbg_cnt		: unsigned(16 downto 0);
	
begin


-- ***********
-- FIFO Buffer
-- ***********

-- Important: FIFO are in SHOWAHEAD mode, rdreq acts like a rdack

dcfifo_gen: for I in 0 to (LINE_BUFFER_N-1) generate	

	dcfifo_buffer: dcfifo
	generic map (
		DELAY_RDUSEDW			=> 1,
		DELAY_WRUSEDW			=> 1,
		LPM_NUMWORDS			=> 512,
		LPM_SHOWAHEAD			=> "ON",
		LPM_WIDTH				=> DATA_BYTES_IN*8,
		OVERFLOW_CHECKING		=> "OFF",
		RDSYNC_DELAYPIPE		=> 5,
		UNDERFLOW_CHECKING	=> "ON",
		USE_EAB					=> "ON",
		WRSYNC_DELAYPIPE		=> 5
	)
	port map (
		data						=> buffer_data(I),
		rdclk						=> out_pixel_clk,
		wrclk						=> sdram_clk,
		wrreq						=> buffer_wrreq(I),
		rdreq						=> buffer_rdreq(I),
		aclr						=> buffer_aclr(I),
		wrempty					=> buffer_wrempty(I),
		rdempty					=> buffer_rdempty(I),	
		q							=> buffer_q(I)
	);

end generate dcfifo_gen;




-- ****************************
-- Write data to VGA controller
-- ****************************

out_data <= out_data_ff;

process(out_pixel_clk, reset) is

begin

	if reset = '1' then
	
		dbg_wr_state <= (others => '1');
	
		-- Reset
		wr_state <= WR_WAITBUFFER_STATE;
		wr_active_buffer 	<= BUFFER_NONE;
		wr_next_buffer 	<= 0;		-- Start with buffer 0
		out_data_ff <= (others => '0');
		out_data_valid <= '0';
		output_byte_n <= 0;
		out_disp_ena_ff <= '0';
		
		
		
		
		
		for I in 0 to LINE_BUFFER_N-1 loop	
			buffer_reset(I) <= '0';
			buffer_valid_ff1(I) <= '0';
			buffer_valid_ff2(I) <= '0';		
			buffer_rdreq(I) <= '0';	
		end loop;	
		
		
		
		
		
		
		for I in 0 to 7 loop	
			wr_line_buffer(I) 	<= (others => '0');
		end loop;
		wr_line_buffer_pos	<= 0;
		wr_line_buffer_req	<= 0;
		wr_line_buffer_rec	<= 0;
		wr_line_buffer_cnt	<= 0;
	
		
		
		
	elsif rising_edge(out_pixel_clk) then
	
		dbg_wr_state <= to_unsigned(0,8);
		
		
		dbg_err_code(0) <= buffer_valid_ff2(wr_active_buffer);
		dbg_err_code(1) <= buffer_valid_ff2(wr_next_buffer);
		
		
		
		for I in 0 to LINE_BUFFER_N-1 loop	
		
			-- Handshake to reset bufferI_valid
			buffer_valid_ff1(I) <= buffer_valid(I);
			buffer_valid_ff2(I) <= buffer_valid_ff1(I);
				
			-- Preset signals			
			buffer_rdreq(I) <= '0';
			
		end loop;
		
		
		-- Line sync FF to detect falling edge
		out_line_sync_ff <= out_line_sync;
	
		-- Preset values
		
		-- clear vga data
		out_data_ff <= (others => '0');
		out_data_valid <= '0';
		
		
		out_disp_ena_ff <= out_disp_ena;
		
		
		
		
		
		case wr_state is
		
		-- wait for the next buffer to be ready
		when WR_WAITBUFFER_STATE =>			
			dbg_wr_state <= to_unsigned(1,8);
			
			
			
			-- next line is ready to write
			if buffer_valid_ff2(wr_next_buffer) = '1' then
				
				wr_active_buffer <= wr_next_buffer;
				
				-- Increase next buffer
				if wr_next_buffer + 1 = LINE_BUFFER_N then
					wr_next_buffer <= 0;
				else
					wr_next_buffer <= wr_next_buffer + 1;
				end if;
				
				
				-- Start buffering data from FIFO
				output_byte_n	<= 0;
				wr_line_buffer_pos	<= 0;
				wr_line_buffer_req	<= 0;
				wr_line_buffer_rec	<= 0;
				wr_line_buffer_cnt	<= 0;
				
				
			
				wr_state <= WR_BUF_REQ_DATA_1;	
			end if;
			
			
		when WR_BUF_REQ_DATA_1 =>		
			-- Request first word from FIFO
			--buffer_rdreq(wr_active_buffer) <= '1';			
			wr_state <= WR_BUF_REQ_DATA_2;	
			
		when WR_BUF_REQ_DATA_2 =>		
			-- Request second word from FIFO
			buffer_rdreq(wr_active_buffer) <= '1';	
			wr_state <= WR_BUF_DATA_1;	
			
		when WR_BUF_DATA_1 =>		
			-- Request first word from FIFO
			wr_line_buffer(0) <= buffer_q(wr_active_buffer)(7 downto 0);
			wr_line_buffer(1) <= buffer_q(wr_active_buffer)(15 downto 8);
			wr_line_buffer(2) <= buffer_q(wr_active_buffer)(23 downto 16);
			wr_line_buffer(3) <= buffer_q(wr_active_buffer)(31 downto 24);		
			wr_state <= WR_BUF_DATA_2;	
			
			buffer_rdreq(wr_active_buffer) <= '1';		
			
		when WR_BUF_DATA_2 =>		
			-- Request second word from FIFO
			wr_line_buffer(4) <= buffer_q(wr_active_buffer)(7 downto 0);
			wr_line_buffer(5) <= buffer_q(wr_active_buffer)(15 downto 8);
			wr_line_buffer(6) <= buffer_q(wr_active_buffer)(23 downto 16);
			wr_line_buffer(7) <= buffer_q(wr_active_buffer)(31 downto 24);
			wr_state <= WR_WAIT_ENA;	
			
			
			--buffer_rdreq(wr_active_buffer) <= '1';	
			
		
			
			
		-- Buffer data from the FIFO in faster line buffer
		when WR_BUF_FIFO_DATA =>
			dbg_wr_state <= to_unsigned(2,8);
			
			
			if wr_line_buffer_cnt < 2  then
				
				-- Read next data word
				buffer_rdreq(wr_active_buffer) <= '1';
				-- Read word from FIFO
				wr_line_buffer(wr_line_buffer_pos + 0) <= buffer_q(wr_active_buffer)(7 downto 0);
				wr_line_buffer(wr_line_buffer_pos + 1) <= buffer_q(wr_active_buffer)(15 downto 8);
				wr_line_buffer(wr_line_buffer_pos + 2) <= buffer_q(wr_active_buffer)(23 downto 16);
				wr_line_buffer(wr_line_buffer_pos + 3) <= buffer_q(wr_active_buffer)(31 downto 24);
				
				wr_line_buffer_pos <= wr_line_buffer_pos + 4;		
				wr_line_buffer_cnt <= wr_line_buffer_cnt + 1;	
				
			else
				wr_line_buffer_cnt <= 0;
				wr_line_buffer_pos <= 0;
				wr_state <= WR_WAIT_ENA;
			end if;
			
			
			
			
			
		when WR_WAIT_ENA =>
			
			if out_disp_ena = '1' and out_disp_ena_ff = '0' then
				wr_state <= WR_DATA_STATE;					
				
				out_data_ff <= wr_line_buffer(wr_line_buffer_pos);
				wr_line_buffer_pos <= wr_line_buffer_pos + 1;			
				out_data_valid <= '1';
			end if;
			
		
		-- Send first byte to vga controller
		when WR_DATA_STATE =>
			dbg_wr_state <= to_unsigned(3,8);			
			
			
			-- End data output if buffer is empty or enable = 0
			if wr_line_buffer_pos >= 8 or out_disp_ena = '0' then
				wr_state <= WR_WAITRESET_STATE;
			
			-- Request next word
			elsif wr_line_buffer_pos >= 3 and buffer_rdempty(wr_active_buffer) = '0' then
			
				wr_line_buffer_pos <= 0;
			
				wr_line_buffer(0) <= wr_line_buffer(4);
				wr_line_buffer(1) <= wr_line_buffer(5);
				wr_line_buffer(2) <= wr_line_buffer(6);
				wr_line_buffer(3) <= wr_line_buffer(7);
		
		
				-- Read next data word
				wr_line_buffer(4) <= buffer_q(wr_active_buffer)(7 downto 0);
				wr_line_buffer(5) <= buffer_q(wr_active_buffer)(15 downto 8);
				wr_line_buffer(6) <= buffer_q(wr_active_buffer)(23 downto 16);
				wr_line_buffer(7) <= buffer_q(wr_active_buffer)(31 downto 24);
				
				-- Read word from FIFO
				buffer_rdreq(wr_active_buffer) <= '1';
			
				out_data_ff <= wr_line_buffer(wr_line_buffer_pos);
				out_data_valid <= '1';
			
			-- Output next byte
			else
				out_data_ff <= wr_line_buffer(wr_line_buffer_pos);
				wr_line_buffer_pos <= wr_line_buffer_pos + 1;			
				out_data_valid <= '1';
			end if;
		
		
		
		
		-- wait for hs with read data state machine
		when WR_WAITRESET_STATE =>
			dbg_wr_state <= to_unsigned(4,8);
			
			-- Reset buffer valid handshake
			buffer_reset(wr_active_buffer) <= '1';
			if buffer_valid_ff2(wr_active_buffer) = '0' then
				buffer_reset(wr_active_buffer) <= '0';
				wr_active_buffer <= BUFFER_NONE;
				wr_state <= WR_WAITBUFFER_STATE;
			end if;
			
		end case; -- wr_state
	
	end if; 
	
end process;




-- *************************************
-- Read data from SDRAM to active buffer
-- *************************************


c_xy_to_address: component xy_to_address
generic map (
	ADDR_WIDTH		=> ADDR_WIDTH,
	RES_WIDTH		=> RES_WIDTH,
	RES_HEIGHT		=> RES_HEIGHT,
	ADDR_X_WIDTH	=> ADDR_X_WIDTH,
	ADDR_Y_WIDTH	=> ADDR_Y_WIDTH,
	DATA_BYTES		=> DATA_BYTES_IN
)
port map 
(
	X         	=> rd_next_addr_x,
	Y         	=> rd_next_addr_y,
	ADDR      	=> rd_next_addr
);

process(sdram_clk, reset) is

begin
	
	if reset = '1' then
		dbg_rd_state <= (others => '1');
	
		-- Reset
		rd_state <= RD_WAITFRAME_STATE;
		sdram_addr <= (others => '0');
		sdram_rd <= '0';
		rd_active <= '0';
		rd_req <= '0';
		rd_next_addr_x  <= (others => '0');
		rd_next_addr_y  <= (others => '0');

		
		rd_active_buffer <= 0;				-- Start with buffer 0
		for I in 0 to LINE_BUFFER_N-1 loop	
			buffer_valid(I) <= '0';
			buffer_reset_ff1(I) <= '0';
			buffer_reset_ff2(I) <= '0';
			
			-- Reset FIFO
			buffer_data(I) <= (others => '0');
			buffer_wrreq(I) <= '0';
			buffer_aclr(I) <= '1';	
		end loop;
	

		-- Reset Request/Receive Counter
		sdram_rd_req_n <= to_unsigned(0,16);
		sdram_rd_rcv_n <= to_unsigned(0,16);
		
	elsif rising_edge(sdram_clk) then
		dbg_rd_state <= to_unsigned(0,8);
		
		
		dbg_err_code(2) <= buffer_valid(rd_active_buffer);
		dbg_err_code(3) <= buffer_valid(rd_active_buffer);
		dbg_err_code(4) <= buffer_wrempty(rd_active_buffer);
		dbg_err_code(5) <= buffer_wrempty(rd_active_buffer);
		dbg_err_code(6) <= out_frame_sync;
		--Debug Request/Receive Counter
		dbg_rcv <= sdram_rd_rcv_n;
		dbg_req <= sdram_rd_req_n;	
		
		
		
		-- FIFO signals		
		for I in 0 to LINE_BUFFER_N-1 loop	
			buffer_data(I) <= (others => '0');
			buffer_wrreq(I) <= '0';
			buffer_aclr(I) <= '0';
		
			-- Handshake to reset bufferX_valid
			buffer_reset_ff1(I) <= buffer_reset(I);
			buffer_reset_ff2(I) <= buffer_reset_ff1(I);
			if buffer_reset_ff2(I) = '1' then
				buffer_valid(I) <= '0';
				buffer_aclr(I) <= '1';	
			end if;
		end loop;
	
		-- Preset signals
		
		-- SDRAM signals
		sdram_rd <= '0';
		rd_active <= '0';
		rd_req <= '0';
		
		out_frame_sync_ff <= out_frame_sync;

		
		
		
		
		-- SDRAM read state machine
		case rd_state is
		
		
		
		
		-- Wait for frame sync to start reading of the first line
		when RD_WAITFRAME_STATE =>
			dbg_rd_state <= to_unsigned(1,8);
		
			-- Rising edge on frame sync
			if out_frame_sync = '1' and out_frame_sync_ff = '0' then				
				rd_state <= RD_WAITBUFFER_STATE;
				--rd_active_buffer <= 0;
				
				-- Reset read address
				rd_next_addr_x <= (others => '0');	
				rd_next_addr_y <= (others => '0');	
			end if;
		
		
		
		
		-- Wait until active buffer is empty to read the next line
		when RD_WAITBUFFER_STATE =>
			dbg_rd_state <= to_unsigned(2,8);
			
			if buffer_valid(rd_active_buffer) = '0' and buffer_wrempty(rd_active_buffer) = '1' then
				rd_state <= RD_REQ_STATE;					
			end if;
		
		
		
		
		-- Request read until rd_en is set
		when RD_REQ_STATE =>
			dbg_rd_state <= to_unsigned(3,8);
		
			--Send read request
			rd_req <= '1';
			
			-- Reset read address	
			rd_next_addr_x <= (others => '0');	
			--rd_next_addr_y <= (others => '0');	
			
			dbg_cnt <= (others => '0');	
			
			-- Init number of requested and received words
			sdram_rd_req_n <= to_unsigned(0,16);
			sdram_rd_rcv_n <= to_unsigned(0,16);
			
			-- Check if read is enabled and SDRAM is ready, then start reading data
			if rd_en = '1' and sdram_wait = '0' then				
				rd_state <= RD_DATA_STATE;
			
				-- Read from first address
				--sdram_rd <= '1';
				--sdram_addr <= rd_next_addr;
				--sdram_rd_req_n <= to_unsigned(1,16);
				
				-- Calculate next address to read
				--rd_next_addr_x  <= to_unsigned(DATA_BYTES_IN,ADDR_X_WIDTH);		
							
				--Set read active
				rd_active <= '1';
			end if;
		
		
		
		
		
		
		
		
		-- Read command was sent to SDRAM, wait for valid data
		when RD_DATA_STATE =>
			dbg_rd_state <= to_unsigned(4,8);

		
			--Set read active
			rd_active <= '1';
			
			-- Check for valid data, then read the data to buffer
			if sdram_data_valid = '1' then 
			
				sdram_rd_rcv_n <= sdram_rd_rcv_n + 1;				
			
				-- Read to buffer
				buffer_data(rd_active_buffer) <= sdram_data;
				buffer_wrreq(rd_active_buffer) <= '1';
										
			end if;
			
			-- Check if SDRAM is ready for next read
			if sdram_wait = '0' then

				-- If line is finished wait for next line to read
				-- If frame is finished wait for next frame
				-- Else read next data 
				if rd_next_addr_x >= RES_WIDTH then
		
					-- Stay in read data state until all requested data is read
					if sdram_rd_rcv_n >= sdram_rd_req_n then
					
						-- Set buffer valid
						buffer_valid(rd_active_buffer) <= '1';
						-- Increase active buffer
						if rd_active_buffer+1 = LINE_BUFFER_N then
							rd_active_buffer <= 0;
						else
							rd_active_buffer <= rd_active_buffer + 1;
						end if;
					
						-- Increase line and reset column
						rd_next_addr_x <= (others => '0');		
						rd_next_addr_y	<= rd_next_addr_y + 1;
						
						--Either wait for the next free buffer or wait for the next frame
						rd_state <= RD_WAITBUFFER_STATE;					
						if rd_next_addr_y + 1 = RES_HEIGHT then
							-- Frame finished
							rd_next_addr_y <= (others => '0');						
							rd_state <= RD_WAITFRAME_STATE;
						end if;						
					end if;
					
					
				else -- line not finished
					
				
					-- stay in read state, read next data
					sdram_rd <= '1';		
					sdram_addr <= rd_next_addr;
					sdram_rd_req_n <= sdram_rd_req_n + 1;
					
					-- Calculate next address to read
					rd_next_addr_x  <= rd_next_addr_x + DATA_BYTES_IN;	
					
				end if;
				
			else -- waitstate requested
			
				-- wait until SDRAM is ready for next read
				rd_state <= RD_REC_WAITREQUEST_STATE_1;
				
			end if;
			
			
		-- There might be pending data requests when entering the wait state caused by the CAS latency
		-- wait until the SDRAM starts sending the requested data
		when RD_REC_WAITREQUEST_STATE_1 =>
			--Set read active
			rd_active <= '1';
			
			-- Check for valid data, then read the data to buffer
			if sdram_data_valid = '1' then
			
				sdram_rd_rcv_n <= sdram_rd_rcv_n + 1;				
			
				-- Read to buffer
				buffer_data(rd_active_buffer) <= sdram_data;
				buffer_wrreq(rd_active_buffer) <= '1';
								
			end if;
			
			if sdram_data_valid = '0' and sdram_wait = '0' then			
				rd_state <=  RD_REC_WAITREQUEST_STATE_2;										
			end if;	
		
		
		
		when RD_REC_WAITREQUEST_STATE_2 =>
			dbg_rd_state <= to_unsigned(5,8);		
			--Set read active
			rd_active <= '1';
			
			-- Check for valid data, then read the data to buffer
			if sdram_data_valid = '1' then
				rd_state <= RD_WAITREQUEST_STATE;										
			end if;	
		
		
		
		-- Line read is not finished yet, wait for SDRAM to be ready for next read
		when RD_WAITREQUEST_STATE =>
			dbg_rd_state <= to_unsigned(6,8);
		
			--Set read active
			rd_active <= '1';
			
			-- Only if there is no more pending data continue with normal read
			if sdram_data_valid = '0' and sdram_wait = '0' then
			
				if sdram_rd_rcv_n >= sdram_rd_req_n then			
			
					-- Calculate next address to read
					rd_next_addr_x  <= rd_next_addr_x;
						
					rd_state <= RD_DATA_STATE;
					
				elsif sdram_rd_rcv_n >= sdram_rd_req_n - 1 then			
			
					-- Calculate next address to read
					rd_next_addr_x  <= rd_next_addr_x - DATA_BYTES_IN;
					
					sdram_rd_req_n <= sdram_rd_req_n - 1;
						
					rd_state <= RD_DATA_STATE;
					
				elsif sdram_rd_rcv_n >= sdram_rd_req_n - 2 then			
			
					-- Calculate next address to read
					rd_next_addr_x  <= rd_next_addr_x - DATA_BYTES_IN- DATA_BYTES_IN;
					
					sdram_rd_req_n <= sdram_rd_req_n - 2;
						
					rd_state <= RD_DATA_STATE;
					
				elsif sdram_rd_rcv_n >= sdram_rd_req_n - 3 then			
			
					-- Calculate next address to read
					rd_next_addr_x  <= rd_next_addr_x - DATA_BYTES_IN- DATA_BYTES_IN- DATA_BYTES_IN;
					
					sdram_rd_req_n <= sdram_rd_req_n - 3;
						
					rd_state <= RD_DATA_STATE;
					
				elsif sdram_rd_rcv_n >= sdram_rd_req_n - 4 then			
			
					-- Calculate next address to read
					rd_next_addr_x  <= rd_next_addr_x - DATA_BYTES_IN- DATA_BYTES_IN- DATA_BYTES_IN- DATA_BYTES_IN;
					
					sdram_rd_req_n <= sdram_rd_req_n - 4;
						
					rd_state <= RD_DATA_STATE;
					
				elsif sdram_rd_rcv_n >= sdram_rd_req_n - 5 then			
			
					-- Calculate next address to read
					rd_next_addr_x  <= rd_next_addr_x - DATA_BYTES_IN- DATA_BYTES_IN- DATA_BYTES_IN- DATA_BYTES_IN- DATA_BYTES_IN;
					
					sdram_rd_req_n <= sdram_rd_req_n - 5;
						
					rd_state <= RD_DATA_STATE;
				end if;
			end if;
			
		end case; -- rd_state
		

	
	end if; 
	
end process;


end architecture a;