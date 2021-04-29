library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity CTU_VGA_V2 is

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
	reset_frame	: in std_logic;				-- reset counter, if a new fram is requested
	reset			: in std_logic;				-- reset all
	Q    			: out unsigned(8 downto 0)	-- data at current coordinate
);
end entity CTU_VGA_V2;


architecture a of CTU_VGA_V2 is
	signal q_next  : unsigned(8 downto 0);		
	signal increment_ff : std_logic; 		-- synchronized increment signal
	signal reset_frame_ff	: std_logic;			-- synchronized new framerequest

begin
	Q <= q_next;

process (clk, reset) is
begin
	
	if reset = '1' then
		q_next <= (others =>'0');
			
	elsif rising_edge (clk) then
		reset_frame_ff <= reset_frame;
		increment_ff <= increment;
		if reset_frame = '1' and reset_frame_ff = '0' then
			q_next <= (others => '0');
		elsif increment = '0' and increment_ff = '1' then	
				q_next <= q_next + 1;
		end if;
	end if;
		
end process;

end a;