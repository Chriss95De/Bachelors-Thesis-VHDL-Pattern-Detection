-- Design Name	: ISOLATED_POINT_GENERATOR
-- File Name	: ISOLATED_POINT_GENERATOR.vhd
-- Function		: Generates 3 points/pixels with a set value on the selected x-position of a line
-- Coder			: Lukas Herbst

library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;


entity ISOLATED_POINT_GENERATOR_2 is
generic(
	ISOLATED_POINT_X_POS_1	: positive:=150;												-- x-position of the isolated point (0-639), but 0 and 1 aren't possible, because of delays (need two clocks to generate an isolated point)
	ISOLATED_POINT_X_POS_2	: positive:=200;												-- x-position of the isolated point (0-639), but 0 and 1 aren't possible, because of delays (need two clocks to generate an isolated point)
	ISOLATED_POINT_X_POS_3	: positive:=250;												-- x-position of the isolated point (0-639), but 0 and 1 aren't possible, because of delays (need two clocks to generate an isolated point)
	ISOLATED_POINT_VALUE_1 	: std_logic_vector (7 downto 0) := "00000000";		-- value of the isolated point
	ISOLATED_POINT_VALUE_2 	: std_logic_vector (7 downto 0) := "00000000";		-- value of the isolated point
	ISOLATED_POINT_VALUE_3 	: std_logic_vector (7 downto 0) := "00000000"		-- value of the isolated point
);
PORT  
(
	clk								: in std_logic;								-- clock
	x_pos_in							: in unsigned(9 downto 0);					-- x-pos
	reset								: in std_logic;								-- reset
	isolated_point_ena_out		: out std_logic;								-- enable signal
	isolated_point_out			: out std_logic_vector (7 downto 0)		-- value of
);
end entity ISOLATED_POINT_GENERATOR_2;


architecture a of ISOLATED_POINT_GENERATOR_2 is
	signal isolated_point_ena	: std_logic;
	signal x_pos_in_ff			: unsigned(9 downto 0); 
	signal isolated_point		: std_logic_vector(7 downto 0);

begin
isolated_point_out 		<= isolated_point;			-- output signal
isolated_point_ena_out	<= isolated_point_ena;		-- output signal

process (reset, clk) is
begin
	if reset = '1' then	-- reset all values
		x_pos_in_ff			 	<= (others => '0');
		isolated_point_ena	<= '0';	
		isolated_point 		<= (others => '0');
		
		
	elsif rising_edge(clk) then
		x_pos_in_ff <= x_pos_in;
		
		if x_pos_in_ff = (ISOLATED_POINT_X_POS_1 - 2) then 	-- generate isolated point at the set x-position (2 x-pos earlier, because it needs two clocks to generate/output it)
			isolated_point_ena	<= '1';
			isolated_point			<= ISOLATED_POINT_VALUE_1;
		elsif x_pos_in_ff = (ISOLATED_POINT_X_POS_2 - 2) then -- generate isolated point at the set x-position (2 x-pos earlier, because it needs two clocks to generate/output it)
			isolated_point_ena	<= '1';
			isolated_point			<= ISOLATED_POINT_VALUE_2;
		elsif x_pos_in_ff = (ISOLATED_POINT_X_POS_3 - 2) then -- generate isolated point at the set x-position (2 x-pos earlier, because it needs two clocks to generate/output it)
			isolated_point_ena	<= '1';
			isolated_point			<= ISOLATED_POINT_VALUE_3;
		else	
			isolated_point_ena	<= '0';
			isolated_point 		<= (others => '0');
		end if;
	end if;
	
end process;

end a;