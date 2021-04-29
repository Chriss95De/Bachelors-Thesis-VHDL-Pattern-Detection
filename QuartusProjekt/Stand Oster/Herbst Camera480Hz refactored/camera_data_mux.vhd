LIBRARY IEEE;
USE IEEE. std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

ENTITY camera_data_mux IS
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
	  
	X         	: out unsigned(9 DOWNTO 0);				-- current data x coodinate
	Y         	: out unsigned(9 DOWNTO 0);				-- current data y coodinate
	DATA      	: out std_logic_vector(15 DOWNTO 0);	-- data at current coordinate
	DATA_VALID	: out std_logic;								--	data is valid -> stays '1' for one line
	BUSY      	: out std_logic								-- frame capture is active
);
END ENTITY camera_data_mux;

ARCHITECTURE a OF camera_data_mux IS
   signal fval_alt :  std_logic;
   signal lval_alt :  std_logic;

	signal START_CAP  :  std_logic;
	signal CAP_ACTIVE :  std_logic;

BEGIN

process(RESET, CLK)
begin



	if RESET = '1' then
	
		X     <= (others => '0');
		Y     <= (others => '0');
		DATA  <= (others => '0');
		DATA_VALID   <= '0';
		
	elsif rising_edge(CLK) then
	
		fval_alt <= FVAL;
      lval_alt <= LVAL;
		
		BUSY <= CAP_ACTIVE;
		
		
		-- LVAL
		if (FVAL = '1') and (LVAL = '1') and (CAP_ACTIVE = '1') then
		
			X     <= X+2;
			Y     <= Y;
			DATA  <= TAP1 & TAP2;
			DATA_VALID   <= '1';
			
			-- LVAL rising edge
			if (lval_alt = '0') then		
				X     <= (others => '0');
				Y     <= Y+1;
			end if;
			
			-- FVAL rising edge
			if (fval_alt = '0') then			
				Y     <= (others => '0');
			end if;
		
		else
		
			DATA_VALID   <= '0';
			
		end if;
		
		if (FVAL = '0') then
		
			-- Frame finished, reset outputs
			X     <= (others => '0');
			Y     <= (others => '0');
			DATA  <= (others => '0');
			DATA_VALID   <= '0';
			
			if(fval_alt = '1') then
				CAP_ACTIVE <= '0';
			end if;
			
			if SINGLE = '1' then
				START_CAP <= '1';
			end if;
			
			if (((START_CAP = '1') and (SINGLE = '0')) or SINGLE_MODE = '0') then
				START_CAP <= '0';
				CAP_ACTIVE <= '1';
			end if;
			
			
		end if;
		

		
	end if;
	end process;

END a;