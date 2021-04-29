

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SDRAM_Write_Buffer is
port (


	-- SDRAM signals
	
	sdram_clk					: in std_logic;								-- SDRAM Clock
	sdram_wait					: in std_logic;								-- SDRAM is busy	
	sdram_data					: out std_logic_vector(15 downto 0);	-- data to SDRAM
	sdram_addr_x				: out unsigned(9 downto 0);				-- Current x position to write
	sdram_addr_y				: out unsigned(8 downto 0); 				-- Current y position to write
	sdram_addr					: out unsigned(19 downto 0);				-- Current memory position to write
	sdram_wr						: out std_logic;								-- SDRAM write command
	
	
	-- SDRAM control signals
	
	wr_en							: in std_logic;							-- Request write access to the SDRAM 
	wr_active					: out std_logic;							-- true while the buffer is writing to the SDRAM
	wr_req						: out std_logic;							-- true until wr_en is set
	
	
	-- CAM signals
	
	cam_clk						: in std_logic;							-- CAM pixel Clock
	cam_data_valid				: in std_logic;							-- Indicates valid data from CAM
	cam_data						: in std_logic_vector(15 downto 0);	-- Current input data	
	cam_line						: in unsigned(15 downto 0);	-- Current line	
	
	
	-- FIFO buffer signals	
	-- FIFO buffer contains data + coordinates
		
	bufferA_data				: out std_logic_vector(15 downto 0); -- Data to buffer
	bufferA_wrreq				: out std_logic;										-- write request
	bufferA_wrclk				: out std_logic;										-- write clock
	bufferA_rdreq				: out std_logic;										-- read request
	bufferA_rdclk				: out std_logic;										-- read clock
	bufferA_aclr				: out std_logic;										-- async clear
	bufferA_wrempty			: in std_logic;										-- write state machine empty signal
	bufferA_rdempty			: in std_logic;										-- read state machine empty signal
	bufferA_q					: in std_logic_vector(15 downto 0);	-- Data from buffer
	
	bufferB_data				: out std_logic_vector(15 downto 0); -- Data to buffer
	bufferB_wrreq				: out std_logic;										-- write request
	bufferB_wrclk				: out std_logic;										-- write clock
	bufferB_rdreq				: out std_logic;										-- read request
	bufferB_rdclk				: out std_logic;										-- read clock
	bufferB_aclr				: out std_logic;										-- async clear
	bufferB_wrempty			: in std_logic;										-- write state machine empty signal
	bufferB_rdempty			: in std_logic;										-- read state machine empty signal
	bufferB_q					: in std_logic_vector(15 downto 0);	-- Data from buffer
	
	-- Other signals
	reset							: in std_logic								-- Async reset
	
	);
end entity SDRAM_Write_Buffer;
	
	
architecture a of SDRAM_Write_Buffer is
	
	
	type active_buffer_type is (BUFFER_NONE, BUFFER_A, BUFFER_B);
	
	
	-- ********************************************************
	-- signals for the write data state machine (FIFO -> SDRAM)
	-- ********************************************************
	
	signal bufferA_line_ff1		: unsigned(15 downto 0);	-- synchronize line data from read state machine to calculate SDRAM address
	signal bufferA_line_ff2		: unsigned(15 downto 0);	-- synchronize line data from read state machine to calculate SDRAM address
	signal bufferB_line_ff1		: unsigned(15 downto 0);	-- synchronize line data from read state machine to calculate SDRAM address
	signal bufferB_line_ff2		: unsigned(15 downto 0);	-- synchronize line data from read state machine to calculate SDRAM address
	
	-- Wait for valid buffer -> Request write access -> Write line <-> SDRAM Waitstate
	--                                                              -> Wait for valid reset
	type wr_state_type is (WR_WAITBUFFER_STATE, WR_REQ_STATE, WR_DATA_STATE, WR_WAITRESET_STATE);
	signal wr_state				: wr_state_type;
	
	signal wr_active_buffer 	: active_buffer_type;
	signal wr_next_buffer 	: active_buffer_type;
		
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
	signal wr_next_addr_x		: unsigned(9 downto 0);
	signal wr_next_addr_y		: unsigned(8 downto 0);
	signal wr_next_addr			: unsigned(19 downto 0);
	
	
	-- *****************************************************
	-- signals for the read data state machine (CAM -> FIFO)
	-- *****************************************************
	
	signal bufferA_line			: unsigned(15 downto 0);	-- contains line number of the current buffer data
	signal bufferB_line			: unsigned(15 downto 0);	-- contains line number of the current buffer data
	
	-- Wait for valid data -> Write data to FIFO -> Wait for next FIFO ready to write
	
	type rd_state_type is (RD_WAITDATA_STATE, RD_DATA_STATE);
	signal rd_state				: rd_state_type;
	
	signal rd_active_buffer 	: active_buffer_type;
	
	signal cam_data_valid_ff	: std_logic; 	-- to detect rising edge
	
	
	-- ******************************
	-- buffer valid handshake signals
	-- ******************************
	
	signal bufferA_valid			: std_logic;	-- Synchronized with cam_clk
															-- Buffer A is filled with valid data for the next line
	signal bufferB_valid			: std_logic;	-- Synchronized with cam_clk
															-- Buffer B is filled with valid data for the next line	
	signal bufferA_valid_ff1	: std_logic;	-- Synchronized with sdram_clk
	signal bufferB_valid_ff1	: std_logic;	-- Synchronized with sdram_clk
	signal bufferA_valid_ff2	: std_logic;	-- Synchronized with sdram_clk
	signal bufferB_valid_ff2	: std_logic;	-- Synchronized with sdram_clk
	
	signal bufferA_reset			: std_logic;	-- Synchronized with sdram_clk
	signal bufferB_reset			: std_logic;	-- Synchronized with sdram_clk
	signal bufferA_reset_ff1	: std_logic;	-- Synchronized with cam_clk
	signal bufferB_reset_ff1	: std_logic;	-- Synchronized with cam_clk
	signal bufferA_reset_ff2	: std_logic;	-- Synchronized with cam_clk
	signal bufferB_reset_ff2	: std_logic;	-- Synchronized with cam_clk
	
begin


-- *******************
-- Write data to SDRAM
-- *******************

c_xy_to_address: component xy_to_address
port map 
(
	X         => wr_next_addr_x,
	Y         => wr_next_addr_y,
	ADDR      => wr_next_addr
);

bufferA_rdclk <= sdram_clk;
bufferB_rdclk <= sdram_clk;

process(sdram_clk, reset) is

begin

	if reset = '1' then
	
		-- Reset
		wr_state <= WR_WAITBUFFER_STATE;
		wr_active_buffer <= BUFFER_NONE;
		wr_next_buffer <= BUFFER_NONE;
		sdram_wr <= '0';
		sdram_data <= (others => '0');
		sdram_addr <= (others => '0');
		sdram_addr_x <= (others => '0');
		sdram_addr_y <= (others => '0');
		wr_next_addr_x <= (others => '0');
		wr_next_addr_y <= (others => '0');		
		wr_active <= '0';
		wr_req <= '0';
		bufferA_reset <= '0';
		bufferB_reset <= '0';
		bufferA_valid_ff1 <= '0';
		bufferB_valid_ff1 <= '0';
		bufferA_valid_ff2 <= '0';
		bufferB_valid_ff2 <= '0';		
		bufferA_rdreq <= '0';
		bufferB_rdreq <= '0';
		
		bufferA_line_ff1 <= (others => '0');		
		bufferA_line_ff2 <= (others => '0');		
		bufferB_line_ff1 <= (others => '0');		
		bufferB_line_ff2 <= (others => '0');		
		
	elsif rising_edge(sdram_clk) then
	
		-- Handshake to reset bufferX_valid
		bufferA_valid_ff1 <= bufferA_valid;
		bufferA_valid_ff2 <= bufferA_valid_ff1;
		bufferB_valid_ff1 <= bufferB_valid;
		bufferB_valid_ff2 <= bufferB_valid_ff1;
		
		-- synchronize line number from read data state machine
		bufferA_line_ff1 <= bufferA_line;
		bufferA_line_ff2 <= bufferA_line_ff1;
		bufferB_line_ff1 <= bufferB_line;
		bufferB_line_ff2 <= bufferB_line_ff1;
		
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
	
		-- Preset values		
		
		bufferA_rdreq <= '0';
		bufferB_rdreq <= '0';
		
		-- Preset signals
		
		-- SDRAM signals
		sdram_wr <= '0';
		sdram_data <= (others => '0');
		wr_active <= '0';
		wr_req <= '0';
		wr_next_addr_x  <= sdram_addr_x;
		wr_next_addr_y  <= sdram_addr_y;
		
		-- FIFO signals
		bufferA_rdreq <= '0';
		bufferB_rdreq <= '0';
		
		
		case wr_state is
		
		-- wait for next buffer filled to write next line to SDRAM
		when WR_WAITBUFFER_STATE =>
			
			-- next line is ready to write
			if wr_next_buffer = BUFFER_A or wr_next_buffer = BUFFER_B then
				
				wr_active_buffer <= wr_next_buffer;
				wr_next_buffer <= BUFFER_NONE;
				
				-- Request write access to SDRAM				
				wr_state <= WR_REQ_STATE;
			
			end if;
		
		-- Wait until write enable for SDRAM
		when WR_REQ_STATE =>
		
			-- Send write request
			wr_req <= '1';
			
			-- Check if write is enabled and SDRAM is ready, then start reading data
			if wr_en = '1' and sdram_wait = '0' then		
			
				wr_state <= WR_DATA_STATE;
			
				-- Read first data word from FIFO
				if wr_active_buffer = BUFFER_A then
					bufferA_rdreq <= '1';
				end if;
				if wr_active_buffer = BUFFER_B then
					bufferB_rdreq <= '1';
				end if;
				
				-- Preset first write address
				sdram_addr_x <= (others => '0');
				wr_next_addr_x <= (others => '0');				
				if wr_active_buffer = BUFFER_A then
					sdram_addr_y <= bufferA_line(8 downto 0);
					wr_next_addr_y <= bufferA_line(8 downto 0);
				end if;
				if wr_active_buffer = BUFFER_B then
					sdram_addr_y <= bufferB_line(8 downto 0);
					wr_next_addr_y <= bufferB_line(8 downto 0);
				end if;
				
				wr_active <= '1';
			end if;
				
		
		-- Send next word to SDRAM
		when WR_DATA_STATE =>
		
			wr_active <= '1';
			
			-- check if buffer is empty -> write is finished
			if wr_active_buffer = BUFFER_A and bufferA_rdempty = '1' then
			
				wr_state <= WR_WAITRESET_STATE;
				wr_active <= '0';	
			
			elsif wr_active_buffer = BUFFER_B  and bufferB_rdempty = '1' then
			
				wr_state <= WR_WAITRESET_STATE;	
				wr_active <= '0';
			
			-- Check if SDRAM is ready for next operation
			elsif sdram_wait = '0' then
			
				-- Send data to SDRAM
				sdram_addr <= wr_next_addr;				
				sdram_wr <= '1';				
				if wr_active_buffer = BUFFER_A then
					sdram_data <= bufferA_q;
				end if;
				if wr_active_buffer = BUFFER_B then
					sdram_data <= bufferB_q;
				end if;
			
				-- Preset address for next write
				wr_next_addr_x <= wr_next_addr_x + 2;
				sdram_addr_x <= sdram_addr_x + 2;
				
				-- Preload data for next write
				if wr_active_buffer = BUFFER_A then
					bufferA_rdreq <= '1';
				end if;
				if wr_active_buffer = BUFFER_B then
					bufferB_rdreq <= '1';
				end if;
			
			else
				
			end if;
		
		-- wait for hs with write data state machine
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



-- ***********************************
-- Read data from CAM to active buffer
-- ***********************************

-- FIFO write clock sync with sdram clock
bufferA_wrclk <= cam_clk;
bufferB_wrclk <= cam_clk;

process(cam_clk, reset) is

begin
	
	if reset = '1' then
	
		-- Reset
		rd_state <= RD_WAITDATA_STATE;
		rd_active_buffer <= BUFFER_NONE;
		bufferA_valid <= '0';
		bufferB_valid <= '0';
		cam_data_valid_ff <= '0';
		bufferA_reset_ff1 <= '0';
		bufferB_reset_ff1 <= '0';
		bufferA_reset_ff2 <= '0';
		bufferB_reset_ff2 <= '0';	
		bufferA_line <= (others => '0');
		bufferB_line <= (others => '0');
		
		-- Reset FIFO
		bufferA_data <= (others => '0');
		bufferA_wrreq <= '0';
		bufferA_aclr <= '1';		
		bufferB_data <= (others => '0');
		bufferB_wrreq <= '0';
		bufferB_aclr <= '1';		
		
	elsif rising_edge(cam_clk) then
	
		-- Preset signals
		
		-- FIFO A signals
		bufferA_data <= (others => '0');
		bufferA_wrreq <= '0';
		bufferA_aclr <= '0';
		
		-- FIFO B signals
		bufferB_data <= (others => '0');
		bufferB_wrreq <= '0';
		bufferB_aclr <= '0';
	
	
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
		
		
		-- FF to detect rising edge of cam_data_valid
		cam_data_valid_ff <= cam_data_valid;
	

		-- CAM read state machine
		case rd_state is
		
		-- Wait for frame sync to start reading of the first line
		when RD_WAITDATA_STATE =>
		
			-- To start at least one buffer need to be empty
			-- And rising edge on cam_data_valid
			if cam_data_valid = '1' and cam_data_valid_ff = '0' and ((bufferA_valid = '0' and bufferA_wrempty = '1') or (bufferB_valid = '0' and bufferB_wrempty = '1')) then				
				
				rd_state <= RD_DATA_STATE;
				
				-- Send first data word
				if bufferA_valid = '0' then
					rd_active_buffer <= BUFFER_A;					
					bufferA_data <= cam_data;
					bufferA_wrreq <= '1';
					bufferA_line <= cam_line;
				elsif bufferB_valid = '0' then
					rd_active_buffer <= BUFFER_B;					
					bufferB_data <= cam_data;
					bufferB_wrreq <= '1';
					bufferB_line <= cam_line;
				end if;
			end if;
				
		-- Read command was sent to SDRAM, wait for valid data
		when RD_DATA_STATE =>
		
			-- Check if there is more data to read
			if cam_data_valid = '1' then
				if rd_active_buffer = BUFFER_A then										
					bufferA_data <= cam_data;
					bufferA_wrreq <= '1';
					bufferA_line <= cam_line;
				elsif rd_active_buffer <= BUFFER_B then										
					bufferB_data <= cam_data;
					bufferB_wrreq <= '1';
					bufferB_line <= cam_line;
				end if;
			else
				if rd_active_buffer = BUFFER_A then		
					bufferA_valid <= '1';
				elsif rd_active_buffer <= BUFFER_B then	
					bufferB_valid <= '1';
				end if;
			
				rd_state <= RD_WAITDATA_STATE;			
			end if;
		
		end case; -- rd_state
	
	end if; 
	
end process;



end architecture a;