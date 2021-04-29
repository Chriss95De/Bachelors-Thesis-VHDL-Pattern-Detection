library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;

-- function:- compare to different signals
--				- set output-signal compare_rdy_out to '1'/TRUE, if the signals have the same value

entity COMPARATOR_x_pos_test is
generic(
	compare_value : positive:=150
);
PORT  
(
	clk					: in std_logic;
	compare_1			: in unsigned(9 DOWNTO 0);
	reset					: in std_logic;
	compare_rdy_out 	: out std_logic;
	compare_out			: out unsigned(9 DOWNTO 0);
	enable				: in std_logic
);
end entity COMPARATOR_x_pos_test;


architecture a of COMPARATOR_x_pos_test is
	type state is (state_1, state_2);
	signal compare_state : state;
	signal compare			: unsigned(9 downto 0);
	signal compare_1_ff	: unsigned(9 DOWNTO 0); -- synchronize compare_1 -> output-signal of flipflop
	signal compare_rdy 	: std_logic;				-- indicates, if compared signals have the same value or not; '1' for same, '0' for different
begin
compare_rdy_out <= compare_rdy;
compare_out <= compare;

process (reset, clk) is
begin
	if reset = '1' then	-- reset all values
		compare_rdy <= '0';	
		compare_1_ff <= (others => '0');
		compare_state <= state_1;
		
	elsif rising_edge(clk) then
		if enable = '0' then
					compare_rdy <= '0';	
					compare_1_ff <= (others => '0');
					compare_state <= state_1;
					compare <= (others => '0');
		
		else
			case compare_state is
		
			when state_1 =>
				compare_1_ff <= compare_1;				-- generates flipflop
				if compare_1_ff >= compare_value then	-- compare the values of two signals
					compare_rdy <= '1';
					compare <= compare_1_ff;
					compare_state <= state_2;
				end if;
		
			when state_2 =>
				compare_rdy <= '1';
				compare <= compare_1_ff;
			end case;
		end if;
	end if;
	
end process;

end a;