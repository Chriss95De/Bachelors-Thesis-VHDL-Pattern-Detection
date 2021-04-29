LIBRARY IEEE;
USE IEEE. std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

ENTITY CTU IS

generic (
RES_HEIGHT					: POSITIVE:= 480	-- Resolution
);

PORT  
(
	clk			: in std_logic;				-- clock for increment
	increment	: in std_logic;				--	increment
	reset			: in std_logic;				-- reset all
	Q    			: out unsigned(8 DOWNTO 0)	-- data at current coordinate
);
END ENTITY CTU;


ARCHITECTURE a OF CTU IS
	signal q_next  : unsigned(8 downto 0);		
	signal increment_ff : std_logic; 		-- synchronized increment signal
BEGIN
	Q <= q_next;

process (clk, reset) is
begin
	
	if reset = '1' then
		q_next <= (others =>'0');
			
	elsif rising_edge (clk) then
		increment_ff <= increment;		
		if increment = '1' and increment_ff = '0' then	
			if q_next +1 <= (RES_HEIGHT -1) then
				q_next <= q_next + 1;
			else
				q_next <= (others => '0');
			end if;
		end if;
	end if;
		
 end process;

END a;