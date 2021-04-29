-- Design Name	: CTU_RD_LINE
-- File Name	: CTU_RD_LINE.vhd
-- Function		: Counter
-- Coder			: Lukas Herbst


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity CTU_RD_LINE is

generic (
	RES_HEIGHT					: POSITIVE:= 480	-- Resolution x
);

PORT  
(
	clk			: in std_logic;				-- clock
	increment	: in std_logic;				--	increment q
	reset			: in std_logic;				-- reset all
	q    			: out unsigned(8 DOWNTO 0)	-- value of next line to be read
);
END ENTITY CTU_RD_LINE;


architecture a of CTU_RD_LINE is
	signal q_next  : unsigned(8 downto 0);	-- next value of q	
	signal increment_ff : std_logic; 		-- synchronized increment signal -> output-signal of flipflop

begin
	q <= q_next;									-- next value to q

process (clk, reset) is
begin
	
	if reset = '1' then							-- reset
		q_next <= (others =>'0');				-- reset value of q
		increment_ff <= '0';						-- reser
			
	elsif rising_edge (clk) then
		increment_ff <= increment;								-- generate flipflop
		if increment = '1' and increment_ff = '0' then	-- check, whether signal q should increment +1
			if q_next +1 <= (RES_HEIGHT -1) then			-- check, whether last line of frame is reached
				q_next <= q_next + 1;							-- increment q_next
			else		
				q_next <= (others => '0');						-- reset q_next, if last line of fram is reached
			end if;
		end if;
	end if;
		
 end process;

END a;