-- Design Name	: SINGLE_LINE_READ_BUFFER
-- File Name	: SINGLE_LINE_READ_BUFFER.vhd
-- Function		: Extract a line of a imagine
-- Coder			: Lukas Herbst

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; 
library altera_mf;
use altera_mf.altera_mf_components.all;


entity SINGLE_LINE_READ_BUFFER is
generic (
	RES_WIDTH					: POSITIVE:= 640;	-- Resolution x
	RES_HEIGHT					: POSITIVE:= 480;	-- Resolution y
	ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
	ADDR_Y_WIDTH				: POSITIVE:= 9;	-- Width of the y address line
	ADDR_WIDTH					: POSITIVE:= 20;	-- Width of the address line
	DATA_BYTES_IN				: POSITIVE:= 4		-- Number of bytes input data line
	);
port (
	-- signals input for reading from sdram
	sdram_clk_rd				: in std_logic;	-- clock of sdram to read data from sdram and to write data into FIFO-Buffer
	sdram_data_in				: in std_logic_vector (DATA_Bytes_IN*8-1 downto 0);	-- Input data from sdram
	sdram_data_in_valid		: in std_logic;	-- Indicates valid data_in from sdram
	sdram_wait					: in std_logic;	-- '1' if sdram is busy
	sdram_rd_en					: in std_logic;	-- disable/enable read attached data at sdram_data_in
	rd_line_next				: in unsigned(ADDR_Y_WIDTH-1 downto 0);	-- next line for reading to FIFO_Buffer
	
	-- signal input for writing to output
	clk_wr						: in std_logic;	-- clock to read data from FIFO_Buffer
	rd_req_in					: in std_logic;	-- read-request of the next Instant
	wr_en							: in std_logic;	-- enable/disable writing data to output
	reset							: in std_logic;	-- asynchron reset
	
	-- signal output for reading from sdram
	sdram_rd						: out std_logic; 		-- SDRAM read command to start reading
	sdram_rd_active			: out std_logic;		-- '1' while buffer is reading from SDRAM
	sdram_rd_req_out			: out std_logic;		-- read-request to MemoryAccessController to read data from sdram
	sdram_rd_addr				: out std_logic_vector (ADDR_WIDTH-1 downto 0);			-- address from which should read data from sdram
	
	-- signal output for writing data to next instance
	data_out						: out std_logic_vector (7 downto 0);		--output data
	data_out_valid				: out std_logic;									-- Indicated valid data_out
	data_rdy						: out std_logic;									-- Requested data are ready to read
	data_out_pos_x				: out unsigned(ADDR_X_WIDTH-1 downto 0);	-- X-Coordinate from data_out-Pixel
	data_out_pos_y				: out unsigned(ADDR_Y_WIDTH-1 downto 0); 	-- Y-Coordinate from data_out-Pixel
	
	-- signal output for debugging
	dbg_rd_state				: out unsigned(7 downto 0);				-- current read state
	dbg_wr_state				: out unsigned(7 downto 0);				-- current write state
	dbg_err_code				: out std_logic_vector(15 downto 0);	-- some debug info
	dbg_rcv						: out unsigned(15 downto 0);	
	dbg_req						: out unsigned(15 downto 0)	
	);
end entity SINGLE_LINE_READ_BUFFER;
	
	
architecture a of SINGLE_LINE_READ_BUFFER is
--	******************
-- FIFO Buffer Data**
--	******************	
	component dcfifo		-- component integratetd in library altera_mf (USER_Manuel"FIFO_Intel_FPGA_IP_USER_Guide")
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
	
	
	--FIFO Buffer Signals
	signal buffer_data		: std_logic_vector(DATA_BYTES_IN*8-1 downto 0);		-- Data to write into FIFO-Buffer
	signal buffer_wrreq		: std_logic; 	-- write-request to write buffer_data into FIFO_Buffer
	signal buffer_rdreq		: std_logic; 	-- read_request to read data from FIFO_Buffer
	signal buffer_aclr		: std_logic;	-- async clear 
	signal buffer_wrempty	: std_logic;	-- write state machine empty signal -> FIFO_Buffer is empty
	signal buffer_rdempty	: std_logic;	-- read state machine empty signal -> FIFO_Buffer is empty
	signal buffer_q			: std_logic_vector(DATA_BYTES_IN*8-1 downto 0);	   -- Output_Data from buffer to write them on data_out
	
	
	-- line number for current buffer_data
	signal buffer_line			: unsigned(ADDR_Y_WIDTH-1 downto 0);		-- contains line numbers of the current buffer data
	signal buffer_line_ff1		: unsigned(ADDR_Y_WIDTH-1 downto 0);		-- synchronize line data from read state machine to calculate SDRAM address
	signal buffer_line_ff2		: unsigned(ADDR_Y_WIDTH-1 downto 0);		-- synchronize line data from read state machine to calculate SDRAM address
	
	
	-- buffer valid handshake signals
	signal buffer_valid		: std_logic;		-- Synchronized with cam_clk, Buffer is filled with valid data for the next line
	signal buffer_valid_ff1	: std_logic;		-- Synchronized with sdram_clk																								
	signal buffer_valid_ff2	: std_logic;		-- Synchronized with sdram_clk	
	signal buffer_reset		: std_logic;		-- Synchronized with sdram_clk
	signal buffer_reset_ff1	: std_logic;		-- Synchronized with cam_clk
	signal buffer_reset_ff2	: std_logic;		-- Synchronized with cam_clk
	
	
	-- signals for the read data state machine
	type rd_state_type is (RD_WAITLINE_STATE, RD_REQ_STATE, RD_DATA_STATE, RD_REC_WAITREQUEST_STATE_1, RD_REC_WAITREQUEST_STATE_2, RD_WAITREQUEST_STATE, RD_WAITBUFFER_STATE);
	signal rd_state				: rd_state_type;
	signal data_FIFO_y			: unsigned(ADDR_Y_WIDTH-1 downto 0); -- stored line in FIFO_Buffer
	signal sdram_rd_req_n		: unsigned(15 downto 0); -- Because of the delay between read request and data valid, to count send requests to sdram
	signal sdram_rd_rcv_n		: unsigned(15 downto 0); -- the number of received words is compared to the number of read requests -> to count received words from sdram
	-- signal dif_req_rcv			: unsigned(15 downto 0); -- difference between number of requested words and received words
	
	
	-- siganls for the write data state machine
	type wr_state_type is (WR_WAITBUFFER_STATE, WR_BUF_REQ_DATA_1,WR_BUF_REQ_DATA_2,WR_BUF_DATA_1,WR_BUF_DATA_2, WR_WAIT_ENA, WR_DATA_STATE, WR_WAITRESET_STATE);
	signal wr_state					: wr_state_type;	
	signal wr_en_ff					: std_logic;
	signal output_byte_n				: integer;	
	signal data_out_ff				: std_logic_vector(7 downto 0);	-- Current output data
	signal data_out_pos_y_ff		: unsigned(ADDR_Y_WIDTH-1 downto 0);
	signal data_out_pos_x_ff		: unsigned(ADDR_X_WIDTH-1 downto 0);
	
	-- Buffer to read whole line from the FIFO
	constant WR_LINE_BUFFER_SIZE : integer := 8;
	type t_wr_line_buffer is array (0 to 7) of std_logic_vector(7 downto 0);
	signal wr_line_buffer	: t_wr_line_buffer;	
	signal wr_line_buffer_pos	: integer; 	-- Next byte position on the line buffer

	
	--*******************************************************
	-- component and signals to calculate next read_address** 
	--*******************************************************
	
	-- Component to resolve coordinates to memory address
	component xy_to_address is
	generic (
		ADDR_WIDTH		: positive;
		RES_WIDTH		: positive;
		RES_HEIGHT		: positive;
		ADDR_X_WIDTH	: positive;
		ADDR_Y_WIDTH	: positive;
		DATA_BYTES		: positive
	);
	port  
	(
		X         : in unsigned(ADDR_X_WIDTH-1 DOWNTO 0);			-- X-Coordinate of Pixel
		Y         : in unsigned(ADDR_Y_WIDTH-1 DOWNTO 0);			-- Y-Coordinate of Pixel
		ADDR      : out std_logic_vector(ADDR_WIDTH-1 DOWNTO 0)	-- data address in sdram
	);
	end component xy_to_address;
	
	-- Connected to xy_to_address, to calculate memory address
	signal rd_next_addr_x		: unsigned(ADDR_X_WIDTH-1 downto 0);			-- X-Coordinate of Pixel
	signal rd_next_addr_y		: unsigned(ADDR_Y_WIDTH-1 downto 0);			-- Y-Coordinate of Pixel
	signal rd_next_addr			: std_logic_vector(ADDR_WIDTH-1 downto 0);	-- data_address in sdram of next data to read
	
	
	
	--*************************************
	-- signal to start reading from sdram**
	--*************************************
	signal rd_req_in_ff	: std_logic;

	
	
	
--*****
--begin
--*****
begin

-- ***********
-- FIFO Buffer
-- ***********
	-- Important: FIFO are in SHOWAHEAD mode, rdreq acts like a rdack	
		dcfifo_buffer: dcfifo	-- component integratetd in library altera_mf (USER_Manuel"FIFO_Intel_FPGA_IP_USER_Guide")
		generic map (	-- Table 3. FIFO Parameters
			DELAY_RDUSEDW			=> 1,
			DELAY_WRUSEDW			=> 1,
			LPM_NUMWORDS			=> 512,					-- "Specifies the depths of the FIFO you require.[...] 2^LPM_WIDTHU"
			LPM_SHOWAHEAD			=> "ON",					-- "Specifies whether the FIFO is in normal mode (OFF) or show-ahead mode (ON)" 
			LPM_WIDTH				=> DATA_BYTES_IN*8,	-- "Specifies the width of the data and q ports [...]"
			OVERFLOW_CHECKING		=> "OFF",
			RDSYNC_DELAYPIPE		=> 5,
			UNDERFLOW_CHECKING	=> "ON",
			USE_EAB					=> "ON",
			WRSYNC_DELAYPIPE		=> 5
		)
		port map ( -- Table 2. Input and Output Ports Description
			data						=> buffer_data,		-- data to write to FIFO_Buffer
			rdclk						=> clk_wr,				-- clock to read data from FIFO_Buffer
			wrclk						=> sdram_clk_rd,		-- clock to write data to FIFO_Buffer
			wrreq						=> buffer_wrreq,		-- "Assert this signal to request for a write operation" 
			rdreq						=> buffer_rdreq,		-- "Assert this signal to request for a read operation"
			aclr						=> buffer_aclr,		-- reset/clear output
			wrempty					=> buffer_wrempty,	-- FIFO_Buffer is empty, delayed version of rdempty
			rdempty					=> buffer_rdempty,	-- FIFO_Buffer is empty
			q							=> buffer_q				-- output data from FIFO_Buffer
		);
	
	
	
	
-- ****************************
-- Write data to Output
-- ****************************

data_out <= data_out_ff;
data_out_pos_x <= data_out_pos_x_ff;
data_out_pos_y <= data_out_pos_y_ff;

process(clk_wr, reset) is
begin

	if reset = '1' then
		dbg_wr_state <= (others => '1');
		-- Reset
		wr_state <= WR_WAITBUFFER_STATE;
		data_out_pos_x_ff <= (others => '0');
		data_out_pos_y_ff <= (others => '0');
		data_out_ff <= (others => '0');
		data_out_valid <= '0';
		output_byte_n <= 0;
		wr_en_ff <= '0';

		buffer_reset <= '0';
		buffer_valid_ff1 <= '0';
		buffer_valid_ff2 <= '0';		
		buffer_rdreq <= '0';	
		buffer_line_ff1 <= (others => '0');		
		buffer_line_ff2 <= (others => '0');		
		
		for I in 0 to 7 loop	
			wr_line_buffer(I) 	<= (others => '0');
		end loop;
		
		wr_line_buffer_pos	<= 0;
	
	
	elsif rising_edge(clk_wr) then
		-- debug status
		dbg_wr_state<= to_unsigned (0,8); 
		dbg_err_code(0) <= buffer_valid_ff2; 
		-- Handshake to reset bufferI_valid
		buffer_valid_ff1 <= buffer_valid;
		buffer_valid_ff2 <= buffer_valid_ff1;
		-- synchronize line number from read data state machine
		buffer_line_ff1 <= buffer_line;
		buffer_line_ff2 <= buffer_line_ff1;	
		-- Preset signals			
		buffer_rdreq <= '0';		
		-- stored line in FIFO
		data_out_pos_y_ff <= data_FIFO_y;
		
		-- Preset values
		
		-- clear out_data
		data_out_ff <= (others => '0');
		data_out_valid <= '0';
		data_rdy <= '0';
		wr_en_ff <= wr_en;
		
		
		case wr_state is
		
		-- wait for the next buffer to be ready
		when WR_WAITBUFFER_STATE =>
			dbg_wr_state <= to_unsigned(1,8);
			if buffer_valid_ff2 = '1' then	-- next line is ready to write
				-- Start buffering data from FIFO
				output_byte_n	<= 0;
				wr_line_buffer_pos	<= 0;
		
				wr_state <= WR_BUF_REQ_DATA_1;	
			end if;
			
			
		-- Request first word from FIFO		
		when WR_BUF_REQ_DATA_1 =>
			dbg_wr_state <= to_unsigned(2,8);
			--buffer_rdreq <= '1';		--  FIFO_Buffer in SHOWAHEAD-Modus	
			wr_state <= WR_BUF_REQ_DATA_2;	
		
	
		-- Request second word from FIFO
		when WR_BUF_REQ_DATA_2 =>	
			dbg_wr_state <= to_unsigned(3,8);
			buffer_rdreq<= '1';	
			wr_state <= WR_BUF_DATA_1;	
		
		
		-- Request first word from FIFO
		when WR_BUF_DATA_1 =>
			dbg_wr_state <= to_unsigned(4,8);
			wr_line_buffer(0) <= buffer_q(7 downto 0);
			wr_line_buffer(1) <= buffer_q(15 downto 8);
			wr_line_buffer(2) <= buffer_q(23 downto 16);
			wr_line_buffer(3) <= buffer_q(31 downto 24);		
			wr_state <= WR_BUF_DATA_2;	
			
			buffer_rdreq <= '1';	
		
		
		-- Request second word from FIFO
		when WR_BUF_DATA_2 =>		
			dbg_wr_state <= to_unsigned(5,8);
			wr_line_buffer(4) <= buffer_q(7 downto 0);
			wr_line_buffer(5) <= buffer_q(15 downto 8);
			wr_line_buffer(6) <= buffer_q(23 downto 16);
			wr_line_buffer(7) <= buffer_q(31 downto 24);
			wr_state <= WR_WAIT_ENA;	
			
			
		-- Wait for signal to start sending data to output	
		when WR_WAIT_ENA => 
			dbg_wr_state <= to_unsigned(6,8);
			data_rdy <= '1';
			if wr_en = '1' and wr_en_ff = '0' then
				wr_state <= WR_DATA_STATE;					
				data_out_ff <= wr_line_buffer(wr_line_buffer_pos);
				wr_line_buffer_pos <= wr_line_buffer_pos + 1;			
				data_out_valid <= '1';
				if data_out_pos_x_ff = 0 then
					data_out_pos_x_ff <= (others => '0');
				else
					data_out_pos_x_ff <= data_out_pos_x_ff + 1;
				end if;
			end if;	
			
		
		-- Send first byte to output
		when WR_DATA_STATE =>
			dbg_wr_state <= to_unsigned(7,8);
			data_rdy <= '1';
			if wr_line_buffer_pos >= 8 or wr_en = '0' then	-- End data output if buffer is empty or enable = 0
				data_rdy <= '0';
				data_out_pos_x_ff <= (others => '0');
				wr_state <= WR_WAITRESET_STATE;
			elsif wr_en = '0' then									-- go back to WR_WAIT_ENA if writing data to output is not enable anymore
				wr_state <= WR_WAIT_ENA;
			elsif wr_line_buffer_pos >= 3 and buffer_rdempty = '0' then	-- Request next word
				wr_line_buffer_pos <= 0;
				wr_line_buffer(0) <= wr_line_buffer(4);
				wr_line_buffer(1) <= wr_line_buffer(5);
				wr_line_buffer(2) <= wr_line_buffer(6);
				wr_line_buffer(3) <= wr_line_buffer(7);
				-- Read next data word
				wr_line_buffer(4) <= buffer_q(7 downto 0);
				wr_line_buffer(5) <= buffer_q(15 downto 8);
				wr_line_buffer(6) <= buffer_q(23 downto 16);
				wr_line_buffer(7) <= buffer_q(31 downto 24);
				-- Read word from FIFO
				buffer_rdreq<= '1';
				data_out_pos_x_ff <= data_out_pos_x_ff + 1;
				data_out_ff <= wr_line_buffer(wr_line_buffer_pos);
				data_out_valid <= '1';
			else	-- Output next byte
				data_out_pos_x_ff <= data_out_pos_x_ff + 1;
				data_out_ff <= wr_line_buffer(wr_line_buffer_pos);
				wr_line_buffer_pos <= wr_line_buffer_pos + 1;			
				data_out_valid <= '1';
			end if;
		
		
		-- wait for hs with read data state machine
		when WR_WAITRESET_STATE =>
			dbg_wr_state <= to_unsigned(8,8);
			-- Reset buffer valid handshake
			buffer_reset <= '1';
			if buffer_valid_ff2 = '0' then
				buffer_reset <= '0';
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
	

process(sdram_clk_rd, reset) is
	begin
	
	if reset = '1' then		-- Reset
		dbg_rd_state <= (others => '1');
		rd_state <= RD_WAITLINE_STATE;
		sdram_rd_addr <= (others => '0');
		sdram_rd <= '0';
		sdram_rd_active <= '0';
		sdram_rd_req_out <= '0';
		rd_next_addr_x  <= (others => '0');
		rd_next_addr_y  <= (others => '0');
		
		data_FIFO_y <= (others => '0');
	
		buffer_valid <= '0';
		buffer_reset_ff1 <= '0';
		buffer_reset_ff2 <= '0';
		buffer_line <= (others => '0');
		-- Reset FIFO
		buffer_data <= (others => '0');
		buffer_wrreq <= '0';
		buffer_aclr <= '1';							-- asynchron clear of FIFO_Buffer
	
		sdram_rd_req_n <= to_unsigned(0,16);	-- Reset Request Counter
		sdram_rd_rcv_n <= to_unsigned(0,16);	-- Reset Receive Counter
	
		
	elsif rising_edge(sdram_clk_rd) then
		-- debug status
		dbg_rd_state <= to_unsigned(0,8);
		dbg_err_code(2) <= buffer_valid;
		dbg_err_code(3) <= buffer_wrempty;
		dbg_err_code(4) <= rd_req_in;
		dbg_rcv <= sdram_rd_rcv_n;
		dbg_req <= sdram_rd_req_n;
		-- FIFO signals		
		buffer_data <= (others => '0');
		buffer_wrreq <= '0';
		buffer_aclr <= '0';
		-- Handshake to reset bufferX_valid
		buffer_reset_ff1 <= buffer_reset;
		buffer_reset_ff2 <= buffer_reset_ff1;
			if buffer_reset_ff2 = '1' then
				buffer_valid <= '0';
				buffer_aclr <= '1';	
			end if;
		
		-- SDRAM signals
		sdram_rd <= '0';
		sdram_rd_active <= '0';
		sdram_rd_req_out <= '0';
		
		-- Read Request In
		rd_req_in_ff <= rd_req_in;
		
		
		--***************************
		-- SDRAM read state machine**
		--***************************
		
		case rd_state is
		
		-- Wait for read_request to start reading a line
		when RD_WAITLINE_STATE =>
			dbg_rd_state <= to_unsigned (1,8); 
			if rd_req_in = '1' and rd_req_in_ff = '0' then		-- Rising edge on read request from next instance		
				rd_state <= RD_WAITBUFFER_STATE;
				rd_next_addr_x <= (others => '0');					-- Reset read address x
				--rd_next_addr_y <= (others => '0');				-- Reset read address y
			end if;

			
		-- Wait until buffer is empty to read the next line
		when RD_WAITBUFFER_STATE =>
			dbg_rd_state <= to_unsigned (2,8); 
			if buffer_valid = '0' and buffer_wrempty = '1' then
				rd_state <= RD_REQ_STATE;					
			end if;	
		
		
		-- Request read until sdram_rd_en is set
		when RD_REQ_STATE =>
			dbg_rd_state <= to_unsigned (3,8); 
			sdram_rd_req_out <= '1';								-- Send read request
			rd_next_addr_x <= (others => '0');					-- Reset read address x		
			sdram_rd_req_n <= to_unsigned(0,16);				-- Init number of requested words
			sdram_rd_rcv_n <= to_unsigned(0,16);				-- Init number of received words
			if sdram_rd_en = '1' and sdram_wait = '0' then	-- Check if read is enabled and SDRAM is ready, then start reading data			
				rd_state <= RD_DATA_STATE;
				sdram_rd_active <= '1';								-- Set read active
			end if;

			
		-- Read command was sent to SDRAM, wait for valid data
		when RD_DATA_STATE =>
			dbg_rd_state <= to_unsigned (4,8); 
			sdram_rd_active <= '1';											--Set read active
			
			if sdram_data_in_valid = '1' then 							-- Check for valid data, then read the data to buffer
				sdram_rd_rcv_n <= sdram_rd_rcv_n + 1;					-- increase received words counter
				buffer_data <= sdram_data_in;								-- Read to buffer
				buffer_wrreq <= '1';											-- set write request to buffer					
			end if;
			
			if sdram_wait = '0' then										-- Check if SDRAM is ready for next read	
				if rd_next_addr_x >= RES_WIDTH then						-- If line is finished wait for next line to read
					if sdram_rd_rcv_n >= sdram_rd_req_n then			-- Stay in read data state until all requested data is read
						buffer_valid <= '1';									-- Set buffer valid				
						data_FIFO_y <= rd_next_addr_y;					-- stored line in FIFO-Buffer
						rd_next_addr_x <= (others => '0');				-- reset column						
						rd_next_addr_y <= rd_line_next;					-- next line, could be the same if not incremented
						rd_state <= RD_WAITLINE_STATE;					-- Wait for next line request
					end if;	
				else 
					sdram_rd <= '1';												-- stay reading
					sdram_rd_addr <= rd_next_addr;							-- set next read address
					sdram_rd_req_n <= sdram_rd_req_n + 1;					-- increase request-counter
					rd_next_addr_x  <= rd_next_addr_x + DATA_BYTES_IN;	-- Calculate next address to read
				end if;
			else -- waitstate requested
				rd_state <= RD_REC_WAITREQUEST_STATE_1;				-- wait until SDRAM is ready for next read	
			end if;
			
			
		-- There might be pending data requests when entering the wait state caused by the CAS latency
		when RD_REC_WAITREQUEST_STATE_1 =>							-- wait until the SDRAM starts sending the requested data
			dbg_rd_state <= to_unsigned (5,8); 
			sdram_rd_active <= '1';										-- Set read active
			
			if sdram_data_in_valid = '1' then						-- Check for valid data, then read the data to buffer
				sdram_rd_rcv_n <= sdram_rd_rcv_n + 1;				-- increase received words counter	
				buffer_data <= sdram_data_in;							-- Read to buffer
				buffer_wrreq <= '1';										-- set write request to buffer					
			end if;
			
			if sdram_data_in_valid = '0' and sdram_wait = '0' then			
				rd_state <=  RD_REC_WAITREQUEST_STATE_2;										
			end if;	
			
			
		when RD_REC_WAITREQUEST_STATE_2 =>		
			dbg_rd_state <= to_unsigned (6,8); 
			sdram_rd_active <= '1';						-- Set read active
			if sdram_data_in_valid = '1' then		-- Check for valid data, then read the data to buffer
				rd_state <= RD_WAITREQUEST_STATE;										
			end if;	
			
			
		when RD_WAITREQUEST_STATE =>
			dbg_rd_state <= to_unsigned (7,8); 
			sdram_rd_active <= '1';						--Set read active
						
			if sdram_data_in_valid = '0' and sdram_wait = '0' then	-- Only if there is no more pending data continue with normal read
			
				if sdram_rd_rcv_n >= sdram_rd_req_n then				
					rd_next_addr_x  <= rd_next_addr_x;	-- Calculate next address to read
					rd_state <= RD_DATA_STATE;
					
				elsif sdram_rd_rcv_n >= sdram_rd_req_n - 1 then			
					rd_next_addr_x  <= rd_next_addr_x - DATA_BYTES_IN;	-- Calculate next address to read
					sdram_rd_req_n <= sdram_rd_req_n - 1;
					rd_state <= RD_DATA_STATE;
					
				elsif sdram_rd_rcv_n >= sdram_rd_req_n - 2 then			
					rd_next_addr_x  <= rd_next_addr_x - DATA_BYTES_IN- DATA_BYTES_IN;	-- Calculate next address to read
					sdram_rd_req_n <= sdram_rd_req_n - 2;	
					rd_state <= RD_DATA_STATE;
					
				elsif sdram_rd_rcv_n >= sdram_rd_req_n - 3 then			
					rd_next_addr_x  <= rd_next_addr_x - DATA_BYTES_IN- DATA_BYTES_IN- DATA_BYTES_IN;	-- Calculate next address to read
					sdram_rd_req_n <= sdram_rd_req_n - 3;	
					rd_state <= RD_DATA_STATE;
					
				elsif sdram_rd_rcv_n >= sdram_rd_req_n - 4 then			
					rd_next_addr_x  <= rd_next_addr_x - DATA_BYTES_IN- DATA_BYTES_IN- DATA_BYTES_IN- DATA_BYTES_IN;	-- Calculate next address to read
					sdram_rd_req_n <= sdram_rd_req_n - 4;	
					rd_state <= RD_DATA_STATE;
					
				elsif sdram_rd_rcv_n >= sdram_rd_req_n - 5 then			
					rd_next_addr_x  <= rd_next_addr_x - DATA_BYTES_IN- DATA_BYTES_IN- DATA_BYTES_IN- DATA_BYTES_IN- DATA_BYTES_IN;	-- Calculate next address to read
					sdram_rd_req_n <= sdram_rd_req_n - 5;
					rd_state <= RD_DATA_STATE;
				end if;
				
			end if;
			
		end case; -- end rd_state
		
	end if; 
	
end process;


end architecture a;
	