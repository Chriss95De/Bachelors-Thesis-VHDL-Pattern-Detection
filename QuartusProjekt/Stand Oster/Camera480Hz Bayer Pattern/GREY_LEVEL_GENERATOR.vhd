-- Design Name	: GREY_LEVEL_GENERATOR
-- File Name	: GREY_LEVEL_GENERATOR.vhd
-- Function		: generates values in grey-levels, increment grey-level by INCREMENT_STEPS, if signal increment change vom '0' to '1'
-- Coder			: Lukas Herbst


library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;


entity GREY_LEVEL_GENERATOR is
generic(
	INCREMENT_STEP	: POSITIVE:= 10									-- increment data by this value, if rising_edge of incrementation signal 
);

port(
	clk				: in std_logic;									-- clock
	increment		: in std_logic;									-- increment value of data_next by INCREMENT_STEP
	reset				: in std_logic;									-- reset all
	data_out     	: out std_logic_vector(7 DOWNTO 0)			-- data 
);
end entity GREY_LEVEL_GENERATOR;

architecture a of GREY_LEVEL_GENERATOR is
	signal data_next_uint 	: unsigned (7 downto 0);			-- next value of data_out (unsigned)
	signal increment_ff 		: std_logic; 							-- synchronized incrementation signal

	
begin																			-- begin description
	data_out <= std_logic_vector(data_next_uint);			-- convert data_next_uint to std_logic_vector

process (reset, clk) is
begin

	if reset = '1' then													-- reset stored values						
		data_next_uint <= (others => '0');	
		
	elsif rising_edge (clk) then
		increment_ff <= increment;										-- generate a flip-flop
	
		if increment_ff and not increment then       			-- increment data_next_uint, if 
		   if data_next_uint > 255 - INCREMENT_STEP then
			  data_next_uint <= (others => '0');
			else
   		  data_next_uint <= data_next_uint + INCREMENT_STEP;	-- increment data_next_uint by INCREMENT_STEP
			end if;
		end if;	

	end if;
 
end process;

end a;