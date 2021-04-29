-- Design Name	: comparator
-- File Name	: comparator.vhd
-- Function		: compares two unsigned signals
-- Coder			: Lukas Herbst

library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;

entity COMPARATOR is

PORT  
(
	clk					: in std_logic;					-- clock
	compare_1			: in unsigned(8 DOWNTO 0);		-- first signal to compare
	compare_2			: in unsigned(8 DOWNTO 0);		-- seceond signal to compare
	reset					: in std_logic;					-- reset
	compare_rdy_out 	: out std_logic					-- true, if the signals have the same value
);
end entity COMPARATOR;


architecture a of COMPARATOR is
	signal compare_1_ff	: unsigned(8 DOWNTO 0); -- synchronize compare_1 -> output-signal of flipflop
	signal compare_2_ff	: unsigned(8 DOWNTO 0);	-- synchronize compare_2 -> output-signal of flipflop
	signal compare_rdy 	: std_logic;				-- indicates, if compared signals have the same value or not; '1' for same, '0' for different

begin
compare_rdy_out <= compare_rdy;

process (reset, clk) is
begin

	if reset = '1' then	-- reset all values
		compare_rdy <= '0';	
		compare_1_ff <= (others => '0');
		compare_2_ff <= (others => '0');
		
	elsif rising_edge(clk) then
		compare_1_ff <= compare_1;				-- generates flipflop
		compare_2_ff <= compare_2;				-- generates flipflop
		if compare_1_ff = compare_2_ff then	-- compare the values of two signals
			compare_rdy <= '1';
		else
			compare_rdy <= '0';
		end if;
		
	end if;
	
end process;

end a;