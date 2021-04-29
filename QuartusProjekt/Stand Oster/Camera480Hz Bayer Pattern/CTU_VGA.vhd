library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity CTU_VGA is

generic (
	RES_HEIGHT	:	POSITIVE:= 480;	-- Resolution
	V_FP	 		:	INTEGER := 10;			--vertical front porch width in rows
	V_PULSE 		:	INTEGER := 2;			--vertical sync pulse width in rows
	V_BP	 		:	INTEGER := 33			--vertical back porch width in rows
);

port  
(
	clk			: in std_logic;				-- clock for increment
	increment	: in std_logic;				--	increment
	reset			: in std_logic;				-- reset all
	Q    			: out unsigned(8 downto 0)	-- data at current coordinate
);
end entity CTU_VGA;


architecture a of CTU_VGA is
	signal q_next  : unsigned(8 downto 0);		
	signal increment_ff : std_logic; 		-- synchronized increment signal

begin
	Q <= q_next;

process (clk, reset) is
begin
	
	if reset = '1' then
		q_next <= (others =>'0');
			
	elsif rising_edge (clk) then
		increment_ff <= increment;	
		if increment = '1' and increment_ff = '0' then	
			if q_next + 1 <= (RES_HEIGHT + V_FP + V_PULSE + V_BP - 1)  then
				q_next <= q_next + 1;
			else
				q_next <= (others => '0');
			end if;
		end if;
	end if;
		
end process;

END a;