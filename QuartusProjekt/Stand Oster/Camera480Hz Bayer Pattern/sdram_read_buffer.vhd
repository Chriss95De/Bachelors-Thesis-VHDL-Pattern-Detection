
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
--  vga_line_sync   |______________|   |__
--                  :              :
--                  :              :    vga_frame_sync  
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
--      4) the vga state machine waits for the vga_bufferX_valid signal to get 0
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
--      vga_pixel_clk -.--------------------------------.-------.
--
--


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SDRAM_Read_Buffer is
port (

	-- SDRAM signals
	sdram_clk					: in std_logic;							-- SDRAM Clock
	sdram_data					: in std_logic_vector(15 downto 0);	-- data from SDRAM
	sdram_data_valid			: in std_logic;							-- Indicates valid data from SDRAM
	sdram_wait					: in std_logic;							-- SDRAM is busy	
	sdram_addr_x				: out unsigned(9 downto 0);			-- Current x position to read
	sdram_addr_y				: out unsigned(8 downto 0); 			-- Current y position to read
	sdram_addr					: out unsigned(19 downto 0);			-- Current memory position to read
	sdram_rd						: out std_logic;							-- SDRAM read command
	
	-- SDRAM control signals
	rd_en							: in std_logic;							-- If read is not active, the next line is only read if rd_en is true 
	rd_active					: out std_logic;							-- true while the buffer is reading from the SDRAM
	rd_req						: out std_logic;							-- true until rd_en is set
	
	-- VGA signals
	vga_pixel_clk				: in std_logic;							-- VGA pixel Clock
	vga_line_sync				: in std_logic;							-- Low active, falling edge when display time ends, rising edge when next line starts
	vga_frame_sync				: in std_logic;							-- Low active, falling edge when display time ends, rising edge when next frame starts
	vga_disp_ena				: in std_logic;							-- Display enable signal
	vga_data						: out std_logic_vector(7 downto 0);	-- Current output data	
	vga_data_valid				: out std_logic;							-- Current output data is valid
	
	-- FIFO buffer signals
	
	bufferA_data				: out std_logic_vector(15 downto 0); -- Data to buffer
	bufferA_wrreq				: out std_logic;							-- write request
	bufferA_wrclk				: out std_logic;							-- write clock
	bufferA_rdreq				: out std_logic;							-- read request
	bufferA_rdclk				: out std_logic;							-- read clock
	bufferA_aclr				: out std_logic;							-- async clear
	bufferA_wrempty			: in std_logic;							-- write state machine empty signal
	bufferA_rdempty			: in std_logic;							-- read state machine empty signal
	bufferA_q					: in std_logic_vector(15 downto 0);	-- Data from buffer
	
	bufferB_data				: out std_logic_vector(15 downto 0); -- Data to buffer
	bufferB_wrreq				: out std_logic;							-- write request
	bufferB_wrclk				: out std_logic;							-- write clock
	bufferB_rdreq				: out std_logic;							-- read request
	bufferB_rdclk				: out std_logic;							-- read clock
	bufferB_aclr				: out std_logic;							-- async clear
	bufferB_wrempty			: in std_logic;							-- write state machine empty signal
	bufferB_rdempty			: in std_logic;							-- read state machine empty signal
	bufferB_q					: in std_logic_vector(15 downto 0);	-- Data from buffer
	
	-- Other signals
	reset							: in std_logic								-- Async reset
	
	);
end entity SDRAM_Read_Buffer;
	
	
architecture a of SDRAM_Read_Buffer is
	
	
	type active_buffer_type is (BUFFER_NONE, BUFFER_A, BUFFER_B);
	
	-- signals for the read data state machine
	
	type rd_state_type is (RD_WAITFRAME_STATE, RD_REQ_STATE, RD_DATA_STATE, RD_WAITREQUEST_STATE, RD_WAITBUFFER_STATE);
	signal rd_state				: rd_state_type;
	
	signal rd_active_buffer 	: active_buffer_type;
	
	
	-- Component to resolve coordinates to memory address
	component xy_to_address is
	port  
	(
		X         : in unsigned(9 DOWNTO 0);     -- (0-641)
		Y         : in unsigned(8 DOWNTO 0);     -- (0-483)
		ADDR      : out unsigned(19 DOWNTO 0)
	);
	end component xy_to_address;
	

	
	-- Connected to xy_to_address, to calculate memory address
	signal rd_next_addr_x		: unsigned(9 downto 0);
	signal rd_next_addr_y		: unsigned(8 downto 0);
	signal rd_next_addr			: unsigned(19 downto 0);
	
	-- siganls for the write data state machine
	
	type wr_state_type is (WR_WAITBUFFER_STATE, WR_DATA_STATE_B1, WR_DATA_STATE_B2, WR_WAITRESET_STATE);
	signal wr_state				: wr_state_type;
	
	signal wr_active_buffer 	: active_buffer_type;
	signal wr_next_buffer 		: active_buffer_type;	
	
	signal vga_line_sync_ff		: std_logic; 	-- to detect falling edge
	
	-- buffer valid handshake signals
	
	signal bufferA_valid			: std_logic;	-- Synchronized with sdram_clk
															-- Buffer A is filled with valid data for the next line
	signal bufferB_valid			: std_logic;	-- Synchronized with sdram_clk
															-- Buffer B is filled with valid data for the next line	
	signal bufferA_valid_ff1	: std_logic;	-- Synchronized with vga_pixel_clk
	signal bufferB_valid_ff1	: std_logic;	-- Synchronized with vga_pixel_clk
	signal bufferA_valid_ff2	: std_logic;	-- Synchronized with vga_pixel_clk
	signal bufferB_valid_ff2	: std_logic;	-- Synchronized with vga_pixel_clk
	
	signal bufferA_reset			: std_logic;	-- Synchronized with vga_pixel_clk
	signal bufferB_reset			: std_logic;	-- Synchronized with vga_pixel_clk
	signal bufferA_reset_ff1	: std_logic;	-- Synchronized with sdram_clk
	signal bufferB_reset_ff1	: std_logic;	-- Synchronized with sdram_clk
	signal bufferA_reset_ff2	: std_logic;	-- Synchronized with sdram_clk
	signal bufferB_reset_ff2	: std_logic;	-- Synchronized with sdram_clk
	
begin





-- ****************************
-- Write data to VGA controller
-- ****************************

bufferA_rdclk <= vga_pixel_clk;
bufferB_rdclk <= vga_pixel_clk;

process(vga_pixel_clk, reset) is

begin

	if reset = '1' then
	
		-- Reset
		wr_state <= WR_WAITBUFFER_STATE;
		wr_active_buffer <= BUFFER_NONE;
		wr_next_buffer <= BUFFER_NONE;
		vga_data <= (others => '0');
		vga_data_valid <= '0';
		bufferA_reset <= '0';
		bufferB_reset <= '0';
		bufferA_valid_ff1 <= '0';
		bufferB_valid_ff1 <= '0';
		bufferA_valid_ff2 <= '0';
		bufferB_valid_ff2 <= '0';		
		bufferA_rdreq <= '0';
		bufferB_rdreq <= '0';
		
	elsif rising_edge(vga_pixel_clk) then
	
		-- Handshake to reset bufferX_valid
		bufferA_valid_ff1 <= bufferA_valid;
		bufferA_valid_ff2 <= bufferA_valid_ff1;
		bufferB_valid_ff1 <= bufferB_valid;
		bufferB_valid_ff2 <= bufferB_valid_ff1;
		
		-- Save the next buffer that is ready for read
		if bufferA_valid_ff2 = '1' and bufferB_valid_ff2 = '0' then
			wr_next_buffer <= BUFFER_A;
		end if;
		if bufferA_valid_ff2 = '0' and bufferB_valid_ff2 = '1' then
			wr_next_buffer <= BUFFER_B;
		end if;
		if bufferA_valid_ff2 = '0' and bufferB_valid_ff2 = '0' then
			wr_next_buffer <= BUFFER_NONE;
		end if;
		
		-- Line sync FF to detect falling edge
		vga_line_sync_ff <= vga_line_sync;
	
		-- Preset values
		
		vga_data <= (others => '0');
		vga_data_valid <= '0';
		
		bufferA_rdreq <= '0';
		bufferB_rdreq <= '0';
		
		case wr_state is
		
		-- wait for line sync and frame sync false to read next line
		when WR_WAITBUFFER_STATE =>
			
			-- start next line
			-- if vga_line_sync_ff = '1' and vga_line_sync = '0' and vga_frame_sync = '0' and (wr_next_buffer = BUFFER_A or wr_next_buffer = BUFFER_B) then
			if vga_disp_ena = '1' and (wr_next_buffer = BUFFER_A or wr_next_buffer = BUFFER_B) then
				
				wr_active_buffer <= wr_next_buffer;
				wr_next_buffer <= BUFFER_NONE;
				
				-- Read first data word
				if wr_next_buffer = BUFFER_A then
					bufferA_rdreq <= '1';
				end if;
				if wr_next_buffer = BUFFER_B then
					bufferB_rdreq <= '1';
				end if;
				
				wr_state <= WR_DATA_STATE_B1;
			
			end if;
		
		-- Send first byte to vga controller
		when WR_DATA_STATE_B1 =>
			
			-- Send first byte to vga controller
			vga_data_valid <= '1';	
			if wr_active_buffer = BUFFER_A then
				vga_data <= bufferA_q(7 downto 0);
			end if;		
			if wr_active_buffer = BUFFER_B then
				vga_data <= bufferB_q(7 downto 0);
			end if;
			
			-- jump to next state
			wr_state <= WR_DATA_STATE_B2;
			
		when WR_DATA_STATE_B2 =>
			
			-- Send second byte to vga controller
			vga_data_valid <= '1';				
			if wr_active_buffer = BUFFER_A then
				vga_data <= bufferA_q(15 downto 8);
			end if;		
			if wr_active_buffer = BUFFER_B then
				vga_data <= bufferB_q(15 downto 8);
			end if;	
			
			-- Check if buffer is empty
			if wr_active_buffer = BUFFER_A then
				if bufferA_rdempty = '1' then
					-- FIFO is empty -> Reset and wait for next line
					wr_state <= WR_WAITRESET_STATE;	
					bufferA_reset <= '1';
				else
					-- Read next data word
					bufferA_rdreq <= '1';
					wr_state <= WR_DATA_STATE_B1;
				end if;
			end if;			
			if wr_active_buffer = BUFFER_B then
				if bufferB_rdempty = '1' then
					-- FIFO is empty -> Reset and wait for next line
					wr_state <= WR_WAITRESET_STATE;	
					bufferB_reset <= '1';
				else
					-- Read next data word
					bufferB_rdreq <= '1';
					wr_state <= WR_DATA_STATE_B1;
				end if;
			end if;			
		
		-- wait for hs with read data state machine
		when WR_WAITRESET_STATE =>
		
			-- Reset buffer valid handshake
			if wr_active_buffer = BUFFER_A then
				bufferA_reset <= '1';
				if bufferA_valid_ff2 = '0' then
					bufferA_reset <= '0';
					wr_active_buffer <= BUFFER_NONE;
					wr_state <= WR_WAITBUFFER_STATE;
				end if;
			end if;
			
			if wr_active_buffer = BUFFER_B then
				bufferB_reset <= '1';
				if bufferB_valid_ff2 = '0' then
					bufferB_reset <= '0';
					wr_active_buffer <= BUFFER_NONE;
					wr_state <= WR_WAITBUFFER_STATE;
				end if;
			end if;
			
		end case; -- wr_state
	
	end if; 
	
end process;




-- *************************************
-- Read data from SDRAM to active buffer
-- *************************************


c_xy_to_address: component xy_to_address
port map 
(
	X         => rd_next_addr_x,
	Y         => rd_next_addr_y,
	ADDR      => rd_next_addr
);

-- FIFO write clock sync with sdram clock
bufferA_wrclk <= sdram_clk;
bufferB_wrclk <= sdram_clk;

process(sdram_clk, reset) is

begin
	
	if reset = '1' then
	
		-- Reset
		rd_state <= RD_WAITFRAME_STATE;
		sdram_addr <= (others => '0');
		sdram_addr_x <= (others => '0');
		sdram_addr_y <= (others => '0');
		sdram_rd <= '0';
		rd_active <= '0';
		rd_req <= '0';
		rd_active_buffer <= BUFFER_NONE;
		rd_next_addr_x  <= (others => '0');
		rd_next_addr_y  <= (others => '0');
		bufferA_valid <= '0';
		bufferB_valid <= '0';
		bufferA_reset_ff1 <= '0';
		bufferB_reset_ff1 <= '0';
		bufferA_reset_ff2 <= '0';
		bufferB_reset_ff2 <= '0';		
		
		-- Reset FIFO
		bufferA_data <= (others => '0');
		bufferA_wrreq <= '0';
		bufferA_aclr <= '1';		
		bufferB_data <= (others => '0');
		bufferB_wrreq <= '0';
		bufferB_aclr <= '1';		
		
	elsif rising_edge(sdram_clk) then
	
		-- Handshake to reset bufferX_valid
		bufferA_reset_ff1 <= bufferA_reset;
		bufferA_reset_ff2 <= bufferA_reset_ff1;
		if bufferA_reset_ff2 = '1' then
			bufferA_valid <= '0';
			bufferA_aclr <= '1';	
		end if;
		bufferB_reset_ff1 <= bufferB_reset;
		bufferB_reset_ff2 <= bufferB_reset_ff1;
		if bufferB_reset_ff2 = '1' then
			bufferB_valid <= '0';
			bufferB_aclr <= '1';	
		end if;
	
		-- Preset signals
		
		-- SDRAM signals
		sdram_rd <= '0';
		rd_active <= '0';
		rd_req <= '0';
		rd_next_addr_x  <= sdram_addr_x;
		rd_next_addr_y  <= sdram_addr_y;
		
		-- FIFO A signals
		bufferA_data <= (others => '0');
		bufferA_wrreq <= '0';
		bufferA_aclr <= '0';
		
		-- FIFO B signals
		bufferB_data <= (others => '0');
		bufferB_wrreq <= '0';
		bufferB_aclr <= '0';
		
		
		-- SDRAM read state machine
		case rd_state is
		
		-- Wait for frame sync to start reading of the first line
		when RD_WAITFRAME_STATE =>
		
			-- To start both buffers need to be empty
		
			if vga_frame_sync = '1' and bufferA_valid = '0' and bufferB_valid = '0' and bufferA_wrempty = '1' and bufferB_wrempty = '1' then				
				rd_state <= RD_REQ_STATE;
				rd_active_buffer <= BUFFER_A;
			end if;
		
		-- Request read until rd_en is set
		when RD_REQ_STATE =>
		
			--Send read request
			rd_req <= '1';
			
			-- Check if read is enabled and SDRAM is ready, then start reading data
			if rd_en = '1' and sdram_wait = '0' then				
				rd_state <= RD_DATA_STATE;
			
				-- Read from first address
				sdram_rd <= '1';
				sdram_addr <= rd_next_addr;
				
				-- Calculate next address to read
				rd_next_addr_x  <= sdram_addr_x + 2;
				
				rd_active <= '1';
			end if;
		
		-- Read command was sent to SDRAM, wait for valid data
		when RD_DATA_STATE =>
		
			rd_active <= '1';
			
			-- Calculate next address to read
			rd_next_addr_x  <= sdram_addr_x + 2;
			
			-- Check for valid data, then read the data to buffer
			if sdram_data_valid = '1' then
			
				if rd_active_buffer = BUFFER_A then
					-- Read to buffer A
					bufferA_data <= sdram_data;
					bufferA_wrreq <= '1';										-- ### Timing issues? Maybe FF for wrreq necessary...
				elsif rd_active_buffer = BUFFER_B then
					-- Read to buffer B
					bufferB_data <= sdram_data;
					bufferB_wrreq <= '1';										-- ### Timing issues? Maybe FF for wrreq necessary...
				end if;
				
				-- Increase the address
				sdram_addr_x <= sdram_addr_x + 2;
				
				-- If line is finished wait for next line to read
				-- If frame is finished wait for next frame
				-- Else read next data 
				if sdram_addr_x >= 640 then				
					-- Line finished
					sdram_addr_x <= (others => '0');
					sdram_addr_y <= sdram_addr_y + 1;					
					rd_state <= RD_WAITBUFFER_STATE;
					
					if sdram_addr_y = 480 - 1 then
						-- Frame finished
						sdram_addr_y <= (others => '0');						
						rd_state <= RD_WAITFRAME_STATE;
					end if;
					
					-- Set buffer valid
					if rd_active_buffer = BUFFER_A then
						bufferA_valid <= '1';
					elsif rd_active_buffer = BUFFER_B then
						bufferB_valid <= '1';
					end if;
					rd_active_buffer <= BUFFER_NONE;
					
				else -- Line not finished	
					
					-- Check if SDRAM is ready for next read
					if sdram_wait = '0' then
						-- stay in read state, read next data
						sdram_rd <= '1';
						sdram_addr <= rd_next_addr;		
					else
						-- wait until SDRAM is ready for next read
						rd_state <= RD_WAITREQUEST_STATE;
					end if;
				
				end if;	
										
			end if;
		
		-- Line read is not finished yet, wait for SDRAM to be ready for next read
		when RD_WAITREQUEST_STATE =>
		
			rd_active <= '1';
			
			-- wait until SDRAM is ready for next read
			if sdram_wait = '0' then
				sdram_rd <= '1';
				rd_state <= RD_DATA_STATE;
			end if;	
		
		-- Line is finished, wait until one buffer is empty to read the next line
		when RD_WAITBUFFER_STATE =>
			
			if bufferA_valid = '0' then
				-- Write next line to buffer A
				rd_state <= RD_REQ_STATE;				
				rd_req <= '1';
				rd_active_buffer <= BUFFER_A;
				
			elsif bufferB_valid = '0' then
				-- Write next line to buffer B
				rd_state <= RD_REQ_STATE;				
				rd_req <= '1';
				rd_active_buffer <= BUFFER_B;
			
			end if;
		
		end case; -- rd_state
	
	end if; 
	
end process;


end architecture a;