library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; 
library altera_mf;
use altera_mf.altera_mf_components.all;


entity SDRAM_Read_Buffer_one_line_gen is
generic (
	LINE_BUFFER_N				: POSITIVE:= 2;	-- Number of lines buffered
	RES_WIDTH					: POSITIVE:= 640;	-- Resolution
	RES_HEIGHT					: POSITIVE:= 480;	-- Resolution
	ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
	ADDR_Y_WIDTH				: POSITIVE:= 9;	-- Width of the y address line
	ADDR_WIDTH					: POSITIVE:= 20;	-- Width of the address line
	DATA_BYTES_IN				: POSITIVE:= 4	-- Number of bytes input data line
	);
port (
	-- line to be read-- 
	line_y						: in unsigned(ADDR_Y_Width-1 downto 0); -- line

	-- SDRAM signals
	sdram_clk					: in std_logic;							-- SDRAM Clock
	sdram_data					: in std_logic_vector(DATA_BYTES_IN*8-1 downto 0);	-- data from SDRAM
	sdram_data_valid			: in std_logic;							-- Indicates valid data from SDRAM
	sdram_wait					: in std_logic;							-- SDRAM is busy
	sdram_addr_x				: out unsigned(ADDR_X_WIDTH-1 downto 0);			-- Current x position to read
	sdram_addr_y				: out unsigned(ADDR_Y_WIDTH-1 downto 0); 			-- Current y position to read
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
end entity SDRAM_Read_Buffer_one_line_gen;
	
	
architecture a of SDRAM_Read_Buffer_one_line_gen is


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



-- *************************************
-- Read data from SDRAM to active buffer
-- *************************************

-- calculate next memory address
rd_next_addr_y = line_y;		-- always read same line

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
		sdram_addr_x <= (others => '0');
		sdram_addr_y <= (others => '0');
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
			buffer_line(I) <= (others => '0');
			
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