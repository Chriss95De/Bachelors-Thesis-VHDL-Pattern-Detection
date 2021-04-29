

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; 
library altera_mf;
use altera_mf.altera_mf_components.all;

entity SDRAM_Write_Buffer_gen is
generic (
	LINE_BUFFER_N				: POSITIVE:= 2;	-- Number of lines buffered
	RES_WIDTH					: POSITIVE:= 640;	-- Resolution
	RES_HEIGHT					: POSITIVE:= 480;	-- Resolution
	ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
	ADDR_Y_WIDTH				: POSITIVE:= 9;	-- Width of the y address line
	ADDR_WIDTH					: POSITIVE:= 20;	-- Width of the address line
	DATA_BYTES					: POSITIVE:= 2		-- Number of bytes data line
	);
port (


	-- SDRAM signals
	
	sdram_clk					: in std_logic;											-- SDRAM Clock
	sdram_wait					: in std_logic;											-- SDRAM is busy	
	sdram_data					: out std_logic_vector(DATA_BYTES*8-1 downto 0);-- data to SDRAM
	sdram_addr					: out std_logic_vector(ADDR_WIDTH-1 downto 0);	-- Current memory position to write
	sdram_wr						: out std_logic;											-- SDRAM write command
	
	
	-- SDRAM control signals
	
	wr_en							: in std_logic;											-- Request write access to the SDRAM 
	wr_active					: out std_logic;											-- true while the buffer is writing to the SDRAM
	wr_req						: out std_logic;											-- true until wr_en is set
	
	
	-- CAM signals
	
	cam_clk						: in std_logic;											-- CAM pixel Clock
	cam_line_active			: in std_logic;											-- Data for one line is arriving
	cam_data_valid				: in std_logic;											-- Indicates valid data from CAM
	cam_data						: in std_logic_vector(DATA_BYTES*8-1 downto 0);	-- Current input data	
	cam_line						: in unsigned(ADDR_Y_WIDTH-1 downto 0);			-- Current line	
	
	-- Other signals
	reset							: in std_logic;											-- Async reset
	
	-- Debugging signals
	dbg_rd_state				: out unsigned(7 downto 0); 				-- Current rd_state
	dbg_wr_state				: out unsigned(7 downto 0); 				-- Current wr_state
	dbg_err_code				: out std_logic_vector(15 downto 0);	-- Some debug information
	dbg_rd						: out unsigned(7 downto 0);	 			-- Some debug information
	dbg_wr						: out unsigned(7 downto 0)	 				-- Some debug information
		
	
	);
end entity SDRAM_Write_Buffer_gen;
	
	
architecture a of SDRAM_Write_Buffer_gen is
	
	signal dbg_wr_fifo				:  unsigned(7 downto 0);		
	signal dbg_rd_fifo				:  unsigned(7 downto 0);
	
	
	
	-- ****************
	-- FIFO Buffer data
	-- ****************
	
	subtype t_active_buffer is integer range 0 to LINE_BUFFER_N;
	constant BUFFER_NONE : t_active_buffer := LINE_BUFFER_N;
		
	component dcfifo
		generic (
			DELAY_RDUSEDW							: POSITIVE;
			DELAY_WRUSEDW							: POSITIVE;		
			LPM_NUMWORDS							: POSITIVE;
			LPM_SHOWAHEAD							: STRING;
			LPM_WIDTH								: POSITIVE;
			OVERFLOW_CHECKING						: STRING;
			RDSYNC_DELAYPIPE						: POSITIVE;
			UNDERFLOW_CHECKING					: STRING;
			USE_EAB									: STRING;
			WRSYNC_DELAYPIPE						: POSITIVE
		);
		port (
			data										: in STD_LOGIC_VECTOR(LPM_WIDTH-1 downto 0);
			rdclk, wrclk, wrreq, rdreq, aclr	: in STD_LOGIC;
			rdfull,wrfull, wrempty, rdempty	: out STD_LOGIC;
			q											: out STD_LOGIC_VECTOR(LPM_WIDTH-1 downto 0);
			rdusedw, wrusedw						: out STD_LOGIC_VECTOR(POSITIVE(CEIL(LOG2(REAL(LPM_NUMWORDS))))-1 downto 0)
		);
	end component;
	
	-- FIFO buffer signals
	
	type t_buffer_data is array (0 to LINE_BUFFER_N-1) of std_logic_vector(DATA_BYTES*8-1 downto 0);
	signal buffer_data		: t_buffer_data; 											-- Data to buffer
	signal buffer_wrreq		: std_logic_vector(LINE_BUFFER_N-1 downto 0);	-- write request
	signal buffer_rdreq		: std_logic_vector(LINE_BUFFER_N-1 downto 0);	-- read request
	signal buffer_aclr		: std_logic_vector(LINE_BUFFER_N-1 downto 0);	-- async clear
	signal buffer_wrempty	: std_logic_vector(LINE_BUFFER_N-1 downto 0);	-- write state machine empty signal
	signal buffer_rdempty	: std_logic_vector(LINE_BUFFER_N-1 downto 0);	-- read state machine empty signal
	signal buffer_q			: t_buffer_data;											-- Data from buffer
	
	-- line number for current buffer data
		
	type t_buffer_line is array (0 to LINE_BUFFER_N-1) of unsigned(ADDR_Y_WIDTH-1 downto 0);
	signal buffer_line			: t_buffer_line;	-- contains line number of the current buffer data
	signal buffer_line_ff1		: t_buffer_line;	-- synchronize line data from read state machine to calculate SDRAM address
	signal buffer_line_ff2		: t_buffer_line;	-- synchronize line data from read state machine to calculate SDRAM address

	-- buffer valid handshake signals
	
	signal buffer_valid		: std_logic_vector(LINE_BUFFER_N-1 downto 0);		-- Synchronized with cam_clk
																										-- Buffer n is filled with valid data for the next line
	signal buffer_valid_ff1	: std_logic_vector(LINE_BUFFER_N-1 downto 0);		-- Synchronized with sdram_clk
	signal buffer_valid_ff2	: std_logic_vector(LINE_BUFFER_N-1 downto 0);		-- Synchronized with sdram_clk	
	signal buffer_reset		: std_logic_vector(LINE_BUFFER_N-1 downto 0);		-- Synchronized with sdram_clk
	signal buffer_reset_ff1	: std_logic_vector(LINE_BUFFER_N-1 downto 0);		-- Synchronized with cam_clk
	signal buffer_reset_ff2	: std_logic_vector(LINE_BUFFER_N-1 downto 0);		-- Synchronized with cam_clk
	
	
	
	
	
	-- ********************************************************
	-- signals for the write data state machine (FIFO -> SDRAM)
	-- ********************************************************

	
	-- Wait for valid buffer -> Request write access -> Write line <-> SDRAM Waitstate
	--                                                              -> Wait for valid reset
	type t_wr_state is (WR_WAITBUFFER_STATE, WR_REQ_STATE, WR_REQ_FIFO_DATA_1, WR_REQ_FIFO_DATA_2, WR_DATA_STATE, WR_BUF_FIFO_DATA, WR_WAIT_STATE, WR_EMPTY_BUF_DATA_1, WR_EMPTY_BUF_DATA_2, WR_WAITRESET_STATE);
	signal wr_state				: t_wr_state;	
	signal wr_active_buffer 	: t_active_buffer;
	signal wr_next_buffer 		: t_active_buffer;
	
		
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
	signal wr_addr_x			: unsigned(ADDR_X_WIDTH-1 downto 0);
	signal wr_addr_y			: unsigned(ADDR_Y_WIDTH-1 downto 0);
	signal wr_addr				: std_logic_vector(ADDR_WIDTH-1 downto 0);
	
	-- Save last sent data to resend if a waitstate occurs
	type t_wr_buffer_data is array (0 to 2) of std_logic_vector(DATA_BYTES*8-1 downto 0);
	type t_wr_buffer_addr is array (0 to 2) of std_logic_vector(ADDR_WIDTH-1 DOWNTO 0);
	type t_wr_buffer_addr_x is array (0 to 2) of unsigned(ADDR_X_WIDTH-1 DOWNTO 0);
	type t_wr_buffer_addr_y is array (0 to 2) of unsigned(ADDR_Y_WIDTH-1 DOWNTO 0);
	signal wr_data_buffer	: t_wr_buffer_data;
	signal wr_addr_buffer	: t_wr_buffer_addr;
	signal wr_addr_x_buffer	: t_wr_buffer_addr_x;
	signal wr_addr_y_buffer	: t_wr_buffer_addr_y;
	
	
	
	-- *****************************************************
	-- signals for the read data state machine (CAM -> FIFO)
	-- *****************************************************
	
	-- Wait for valid data -> Write data to FIFO -> Wait for next FIFO ready to write
	
	type t_rd_state is (RD_WAITDATA_STATE, RD_DATA_STATE);
	signal rd_state				: t_rd_state;
	
	signal rd_active_buffer 	: t_active_buffer;
	
	signal cam_data_valid_ff	: std_logic; 	-- to detect rising edge
	signal cam_line_active_ff	: std_logic; 	-- to detect rising edge
	
	
	
begin

-- ***********
-- FIFO Buffer
-- ***********

dcfifo_gen: for I in 0 to (LINE_BUFFER_N-1) generate	

	dcfifo_buffer: dcfifo
	generic map (
		DELAY_RDUSEDW			=> 1,
		DELAY_WRUSEDW			=> 1,
		LPM_NUMWORDS			=> 512,
		LPM_SHOWAHEAD			=> "OFF",
		LPM_WIDTH				=> DATA_BYTES*8,
		OVERFLOW_CHECKING		=> "OFF",
		RDSYNC_DELAYPIPE		=> 5,
		UNDERFLOW_CHECKING	=> "ON",
		USE_EAB					=> "ON",
		WRSYNC_DELAYPIPE		=> 5
	)
	port map (
		data						=> buffer_data(I),
		rdclk						=> sdram_clk,
		wrclk						=> cam_clk,
		wrreq						=> buffer_wrreq(I),
		rdreq						=> buffer_rdreq(I),
		aclr						=> buffer_aclr(I),
		wrempty					=> buffer_wrempty(I),
		rdempty					=> buffer_rdempty(I),	
		q							=> buffer_q(I)
	);

end generate dcfifo_gen;


-- *******************
-- Write data to SDRAM
-- *******************

-- Calculate current momory address
c_xy_to_address: component xy_to_address
generic map (
	ADDR_WIDTH		=> ADDR_WIDTH,
	RES_WIDTH		=> RES_WIDTH,
	RES_HEIGHT		=> RES_HEIGHT,
	ADDR_X_WIDTH	=> ADDR_X_WIDTH,
	ADDR_Y_WIDTH	=> ADDR_Y_WIDTH,
	DATA_BYTES		=> DATA_BYTES
)
port map 
(
	X         	=> wr_addr_x,
	Y         	=> wr_addr_y,
	ADDR      	=> wr_addr
);

process(sdram_clk, reset) is

begin

	if reset = '1' then
	
		-- Reset
		dbg_rd_fifo <= (others => '0');
		dbg_wr_state <= (others => '1');
		wr_state 			<= WR_WAITBUFFER_STATE;
		wr_active_buffer 	<= BUFFER_NONE;
		wr_next_buffer 	<= 0;		-- Start with buffer 0
		sdram_wr 			<= '0';
		sdram_data 			<= (others => '0');
		sdram_addr 			<= (others => '0');
		wr_addr_x 			<= (others => '0');
		wr_addr_y 			<= (others => '0');		
		wr_active 			<= '0';
		wr_req 				<= '0';
		
		wr_data_buffer 	<= (others => (others => '0'));
		wr_addr_buffer 	<= (others => (others => '0'));
		wr_addr_x_buffer	<= (others => (others => '0'));
		wr_addr_y_buffer 	<= (others => (others => '0'));
		
		for I in 0 to LINE_BUFFER_N-1 loop	
			buffer_reset(I) <= '0';
			buffer_valid_ff1(I) <= '0';
			buffer_valid_ff2(I) <= '0';		
			buffer_rdreq(I) <= '0';
			
			buffer_line_ff1(I) <= (others => '0');		
			buffer_line_ff2(I) <= (others => '0');	
		end loop;	
		
	elsif rising_edge(sdram_clk) then
	
		dbg_wr_state <= to_unsigned(0,8);
		
		for I in 0 to LINE_BUFFER_N-1 loop	
		
			-- Handshake to reset bufferI_valid
			buffer_valid_ff1(I) <= buffer_valid(I);
			buffer_valid_ff2(I) <= buffer_valid_ff1(I);
			
			-- synchronize line number from read data state machine
			buffer_line_ff1(I) <= buffer_line(I);
			buffer_line_ff2(I) <= buffer_line_ff1(I);
				
			-- Preset signals			
			buffer_rdreq(I) <= '0';
			
		end loop;
		
		-- Preset signals
		
		-- SDRAM signals
		sdram_wr <= '0';
		sdram_data <= (others => '0');
		wr_active <= '0';
		wr_req <= '0';	
		
		
		-- Write data state machine		
		
		case wr_state is
		
		-- wait for next buffer filled to write next line to SDRAM
		when WR_WAITBUFFER_STATE =>
		
			dbg_wr_state <= to_unsigned(1,8);	
			
			
			dbg_rd <= dbg_rd_fifo;
			
			-- next line is ready to write
			if buffer_valid_ff2(wr_next_buffer) = '1' then
				
				wr_active_buffer <= wr_next_buffer;
				
				-- Increase next buffer
				if wr_next_buffer + 1 = LINE_BUFFER_N then
					wr_next_buffer <= 0;
				else
					wr_next_buffer <= wr_next_buffer + 1;
				end if;
				
				-- Preset first write address
				wr_addr_x <= (others => '0');
				wr_addr_y <= buffer_line_ff2(wr_next_buffer);
				
				-- Request write access to SDRAM				
				wr_state <= WR_REQ_STATE;
			
			end if;
		
		-- Wait until write enable for SDRAM
		when WR_REQ_STATE =>		
			-- Send write request
			wr_req <= '1';			
			-- Check if write is enabled and SDRAM is ready, then start reading data
			if wr_en = '1' and sdram_wait = '0' then	
				dbg_rd_fifo <= (others => '0');			
				-- Set write active
				wr_active <= '1';				
				-- Request data from the FIFO
				wr_state <= WR_REQ_FIFO_DATA_1;
			end if;		
		
		
		
		
		
		-- Send data requests to FIFO Buffer
		-- Request is registered by the FIFO on the next clock
		-- Data is avaiable on the overnext clock
		when WR_REQ_FIFO_DATA_1 =>
			-- Set write active
			wr_active <= '1';			
			-- Request next data from FIFO
			buffer_rdreq(wr_active_buffer) <= '1';			
			wr_state <= WR_REQ_FIFO_DATA_2;
		when WR_REQ_FIFO_DATA_2 =>
			-- Set write active
			wr_active <= '1';			
			-- Request next data from FIFO
			buffer_rdreq(wr_active_buffer) <= '1';
			--Start writing data to SDRAM
			wr_state <= WR_DATA_STATE;
		
		
		
		-- Send next word to SDRAM
		when WR_DATA_STATE =>
		
			-- Set write active
			wr_active <= '1';
						
			
			
					
			-- Check if SDRAM is ready for next operation
			if sdram_wait = '0' then
			
				dbg_rd_fifo <= dbg_rd_fifo + 1;
			
				-- Send next data to SDRAM
				sdram_addr <= wr_addr;				
				sdram_wr <= '1';	
				sdram_data <= buffer_q(wr_active_buffer);
				
				-- Save data in case of waitstate request
				-- Data has to be resent if a waitstate occurs
				wr_data_buffer(0) <= buffer_q(wr_active_buffer);	
				wr_addr_buffer(0) <= wr_addr;
				wr_addr_x_buffer(0) <= wr_addr_x;
				wr_addr_y_buffer(0) <= wr_addr_y;
			
				-- Preset address for next write
				wr_addr_x <= wr_addr_x + DATA_BYTES;
				
				-- Request next data
				buffer_rdreq(wr_active_buffer) <= '1';
				
				-- check if line is finished
				if wr_addr_x + DATA_BYTES >= RES_WIDTH then			
					wr_state <= WR_WAITRESET_STATE;
				end if;
				
			
			-- Waitstate Request
			else		
				dbg_rd_fifo <= dbg_rd_fifo - 1;	
				
				-- Save next data to send after wait state
				wr_data_buffer(1) <= buffer_q(wr_active_buffer);	
				wr_addr_buffer(1) <= wr_addr;
				wr_addr_x_buffer(1) <= wr_addr_x;
				wr_addr_y_buffer(1) <= wr_addr_y;
				
				-- Preset address for next write
				wr_addr_x <= wr_addr_x + DATA_BYTES;
				
				-- Buffer next requested FIFO data
				wr_state <= WR_BUF_FIFO_DATA;
				
			end if;
			
			
			
		
			
		-- Buffer requested FIFO data
		when WR_BUF_FIFO_DATA =>
			-- Set write active
			wr_active <= '1';		
			-- Save next data to send after wait state
			wr_data_buffer(2) <= buffer_q(wr_active_buffer);	
			wr_addr_buffer(2) <= wr_addr;
			wr_addr_x_buffer(2) <= wr_addr_x;
			wr_addr_y_buffer(2) <= wr_addr_y;
			-- Preset address for next write
			wr_addr_x <= wr_addr_x + DATA_BYTES;	
			-- Jump to waitstate
			wr_state <= WR_WAIT_STATE;		
			
		-- Wait Request state
		when WR_WAIT_STATE =>		
			-- Set write active
			wr_active <= '1';						
			-- after wait state is finished, resend buffered data
			if sdram_wait = '0' then	
				dbg_rd_fifo <= dbg_rd_fifo + 1;		
				-- Send next data to SDRAM
				sdram_addr <= wr_addr_buffer(0);				
				sdram_wr <= '1';	
				sdram_data <= wr_data_buffer(0);	
				-- Empty buffered data
				wr_state <= WR_EMPTY_BUF_DATA_1;
				
				-- check if line is finished
				if wr_addr_x_buffer(0) + DATA_BYTES >= RES_WIDTH then			
					wr_state <= WR_WAITRESET_STATE;
				end if;
			end if;
			
		-- Send buffered data after wait state
		when WR_EMPTY_BUF_DATA_1 =>			
			-- Set write active
			wr_active <= '1';		
		
			if sdram_wait = '0' then		
				dbg_rd_fifo <= dbg_rd_fifo + 1;	
				-- Send next data to SDRAM
				sdram_addr <= wr_addr_buffer(1);				
				sdram_wr <= '1';	
				sdram_data <= wr_data_buffer(1);
				-- Empty buffered data
				wr_state <= WR_EMPTY_BUF_DATA_2;	
					
				-- check if line is finished
				if wr_addr_x_buffer(1) + DATA_BYTES >= RES_WIDTH then			
					wr_state <= WR_WAITRESET_STATE;
				end if;
			else
				-- If another wait state occurs, resend whole buffer
				dbg_rd_fifo <= dbg_rd_fifo - 1;
				wr_state <= WR_WAIT_STATE;
			end if;
			
		when WR_EMPTY_BUF_DATA_2 =>					
			-- Set write active
			wr_active <= '1';		
		
			if sdram_wait = '0' then
		
				dbg_rd_fifo <= dbg_rd_fifo + 1;	

				-- Send next data to SDRAM
				sdram_addr <= wr_addr_buffer(2);				
				sdram_wr <= '1';
				sdram_data <= wr_data_buffer(2);
				-- Save buffer 2 if in next write state a new wait state occurs
				wr_data_buffer(0) <= wr_data_buffer(2);
				wr_addr_buffer(0) <= wr_addr_buffer(2);
				wr_addr_x_buffer(0) <= wr_addr_x_buffer(2);
				wr_addr_y_buffer(0) <= wr_addr_y_buffer(2);
				--Reset remaining buffer
				wr_data_buffer(1) <= (others => '0');
				wr_addr_buffer(1) <= (others => '0');
				wr_addr_x_buffer(1) <= (others => '0');
				wr_addr_y_buffer(1) <= (others => '0');
				wr_data_buffer(2) <= (others => '0');
				wr_addr_buffer(2) <= (others => '0');
				wr_addr_x_buffer(2) <= (others => '0');
				wr_addr_y_buffer(2) <= (others => '0');
				-- Continue regular data write
				wr_state <= WR_REQ_FIFO_DATA_1;	
					
				-- check if line is finished
				if wr_addr_x_buffer(2) + DATA_BYTES >= RES_WIDTH then			
					wr_state <= WR_WAITRESET_STATE;
				end if;	
			else
				-- If another wait state occurs, resend whole buffer
				dbg_rd_fifo <= dbg_rd_fifo - 2;
				wr_state <= WR_WAIT_STATE;
			end if;	
		
		
		
		
		
		-- wait for hs with write data state machine
		when WR_WAITRESET_STATE =>
		
			dbg_wr_state <= to_unsigned(5,8);
		
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



-- ***********************************
-- Read data from CAM to active buffer
-- ***********************************

process(cam_clk, reset) is
	
begin
	
	if reset = '1' then
	
		dbg_rd_state <= (others => '1');
		dbg_wr_fifo <= (others => '0');
	
		-- Reset
		rd_state <= RD_WAITDATA_STATE;
		rd_active_buffer <= 0;				-- Start with buffer 0
		cam_data_valid_ff <= '0';
		cam_line_active_ff <= '0';
		
		
		for I in 0 to LINE_BUFFER_N-1 loop	
			buffer_valid(I) <= '0';
			buffer_reset_ff1(I) <= '0';
			buffer_reset_ff2(I) <= '0';
			buffer_line(I) <= (others => '0');
			
			-- Reset FIFO
			buffer_data(I) <= (others => '0');
			buffer_wrreq(I) <= '0';
			buffer_aclr(I) <= '1';	
		end loop;
		
	elsif rising_edge(cam_clk) then	
		
		dbg_rd_state <= to_unsigned(0,8);
	
		-- Preset signals
		
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
		
		-- FF to detect rising edge of cam_data_valid
		cam_data_valid_ff <= cam_data_valid;
		-- FF to detect rising edge of cam_line_active
		cam_line_active_ff <= cam_line_active;
	

		-- CAM read state machine
		case rd_state is
		
		-- Wait for frame sync to start reading of the first line
		when RD_WAITDATA_STATE =>
		
			dbg_rd_state <= to_unsigned(1,8);
			
			dbg_wr <= dbg_wr_fifo;
		
			-- To start the next line buffer need to be empty						
			-- rising edge on cam_data_valid
			if cam_data_valid = '1' and cam_data_valid_ff = '0' and buffer_valid(rd_active_buffer) = '0' and buffer_wrempty(rd_active_buffer) = '1' then				
				
				rd_state <= RD_DATA_STATE;
				
				-- Send first data word				
				buffer_data(rd_active_buffer) <= cam_data;
				buffer_wrreq(rd_active_buffer) <= '1';
				buffer_line(rd_active_buffer) <= cam_line;
				
				
				
				dbg_wr_fifo <= (others => '0');
			end if;
				
		-- Read command was sent to SDRAM, wait for valid data
		when RD_DATA_STATE =>
		
			dbg_rd_state <= to_unsigned(2,8);
		
			-- Check if there is more data to read
			if cam_data_valid = '1' then									
				buffer_data(rd_active_buffer) <= cam_data;
				buffer_wrreq(rd_active_buffer) <= '1';
				
				
				dbg_wr_fifo <= dbg_wr_fifo + 1;
			elsif cam_line_active = '0' then
				buffer_valid(rd_active_buffer) <= '1';
				
				-- Increase active buffer
				if rd_active_buffer+1 = LINE_BUFFER_N then
					rd_active_buffer <= 0;
				else
					rd_active_buffer <= rd_active_buffer + 1;
				end if;
				
				rd_state <= RD_WAITDATA_STATE;			
			end if;
		
		end case; -- rd_state
	
	end if; 
	
end process;



end architecture a;