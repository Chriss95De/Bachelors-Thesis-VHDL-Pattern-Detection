LIBRARY IEEE;
USE IEEE. std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

ENTITY camera_data_mux_gen IS
GENERIC (
	RES_WIDTH					: POSITIVE:= 640;	-- Resolution
	RES_HEIGHT					: POSITIVE:= 480;	-- Resolution
	ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
	ADDR_Y_WIDTH				: POSITIVE:= 9;	-- Width of the y address line
	DATA_BYTES					: POSITIVE:= 2		-- Number of bytes data line (2 or 4)
	);
PORT  
(
	RESET     	:  in std_logic;								-- Async Reset
	CLK       	:  in std_logic;								-- Camera Pixel Clock
	SINGLE_MODE	:  in std_logic;								-- '0' continuous mode; '1' single shot mode
	SINGLE    	:  in std_logic;								-- single shot on rising edge
	LVAL      	:  in std_logic;
	FVAL      	:  in std_logic;
	TAP1      	:  in std_logic_vector(7 DOWNTO 0);
	TAP2      	:  in std_logic_vector(7 DOWNTO 0);	  
	BUSY      	: out std_logic;							-- frame capture is active
	LINE_ACTIVE	: out std_logic;
	DATA_VALID	: out std_logic;								--	data is valid -> stays '1' for one line
	DATA      	: out std_logic_vector(DATA_BYTES*8-1 DOWNTO 0);	-- data at current coordinate
	X         	: out unsigned(ADDR_X_WIDTH-1 DOWNTO 0);				-- current data x coodinate
	Y         	: out unsigned(ADDR_Y_WIDTH-1 DOWNTO 0)				-- current data y coodinate
);
END ENTITY camera_data_mux_gen;

ARCHITECTURE a OF camera_data_mux_gen IS
   signal FVAL_ff :  std_logic;
   signal LVAL_ff :  std_logic;
	signal SINGLE_ff1 : std_logic;
	signal SINGLE_ff2 : std_logic;
	
	type t_state is (WAIT_STATE, WAITFRAME_STATE, WAITLINE_STATE, DATA_OUT_16BIT, DATA_OUT_32BIT_1, DATA_OUT_32BIT_2);
	signal state				: t_state;
	
	signal DATA_TMP : std_logic_vector(15 DOWNTO 0);
	

BEGIN

process(RESET, CLK)
begin




	if RESET = '1' then
	
		X     <= (others => '0');
		Y     <= (others => '0');
		DATA  <= (others => '0');
		DATA_TMP <= (others => '0');
		DATA_VALID   <= '0';
		LINE_ACTIVE <= '0';	
		BUSY <= '0';
		
		state <= WAIT_STATE;
		
	elsif rising_edge(CLK) then
		
		SINGLE_ff1 <= SINGLE;
		SINGLE_ff2 <= SINGLE_ff1;
	
		FVAL_ff <= FVAL;
      LVAL_ff <= LVAL;
		
		BUSY <= '0';
		DATA_VALID   <= '0';
		LINE_ACTIVE <= '0';	
		
		case state is
		
		-- Wait for continuous mode or single shot trigger
		when WAIT_STATE =>
		
			X <= (others => '0');
			Y <= (others => '0');
		
		
			if SINGLE_MODE = '0' or (SINGLE_ff2 = '1' and SINGLE_ff1 = '0') then
				BUSY <= '1';
				state <= WAITFRAME_STATE;
			end if;
		
		-- Wait for the end of the current frame
		when WAITFRAME_STATE =>
		
			BUSY <= '1';
			
			if FVAL = '1' and FVAL_ff = '0' then
				state <= WAITLINE_STATE;
			end if;
		
		-- Wait for start of next line
		when WAITLINE_STATE =>
			
			BUSY <= '1';
			
			-- rising edge FVAL
			if LVAL_ff = '0' and LVAL = '1' then
			
				if DATA_BYTES = 4 then
					DATA_TMP(15 downto 8) <= TAP2;
					DATA_TMP(7 downto 0) <= TAP1;
					state <= DATA_OUT_32BIT_1;
					LINE_ACTIVE <= '1';	
				else
					state <= DATA_OUT_16BIT;
					-- output first word
					DATA(15 downto 0) <= TAP2 & TAP1;
					DATA_VALID <= '1';	
					LINE_ACTIVE <= '1';	
				end if;
			end if;
		
		when DATA_OUT_16BIT =>
			
			BUSY <= '1';
			LINE_ACTIVE <= '1';
			
			DATA(15 downto 0) <= TAP2 & TAP1;
			DATA_VALID <= '1';
			
			X <= X + 2;			
			
			if X+2 >= RES_WIDTH then
				Y <= Y+1;
				X <= (others => '0');
				
				if Y+1 >= RES_HEIGHT then
					state <= WAIT_STATE;
				else
					state <= WAITLINE_STATE;
				end if;
			end if;
			
		
		when DATA_OUT_32BIT_1 =>
			
			BUSY <= '1';
			LINE_ACTIVE <= '1';
			
			--DATA(7 downto 0) <= TAP2;
			--DATA(31 downto 24) <= TAP1;
			--DATA(23 downto 16) <= DATA_TMP(15 downto 8);
			--DATA(15 downto 8) <= DATA_TMP(7 downto 0);
			DATA(7 downto 0) <= DATA_TMP(7 downto 0);
			DATA(15 downto 8) <= DATA_TMP(15 downto 8);
			DATA(23 downto 16) <= TAP1;
			DATA(31 downto 24) <= TAP2;
			DATA_VALID <= '1';		
			
			state <= DATA_OUT_32BIT_2;

		
		when DATA_OUT_32BIT_2 =>

			BUSY <= '1';
			LINE_ACTIVE <= '1';
	
			DATA_TMP(15 downto 8) <= TAP2;
			DATA_TMP(7 downto 0) <= TAP1;
			
			state <= DATA_OUT_32BIT_1;		
			DATA_VALID <= '0';
			
			
			X <= X + 4;	
						
			if X+4 >= RES_WIDTH then
				Y <= Y+1;
				X <= (others => '0');
				
				if Y+1 >= RES_HEIGHT then
					state <= WAIT_STATE;
				else
					state <= WAITLINE_STATE;
				end if;
			end if;
		
		end case; -- state
		
	end if;
		
		
		
end process;

END a;