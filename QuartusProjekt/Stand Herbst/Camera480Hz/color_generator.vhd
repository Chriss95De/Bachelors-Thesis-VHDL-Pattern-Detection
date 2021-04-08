LIBRARY IEEE;
USE IEEE. std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

ENTITY color_generator IS

PORT  
(
	increase		: in std_logic;
	reset			: in std_logic;
	DATA      	: out std_logic_vector(7 DOWNTO 0)	-- data at current coordinate
);
END ENTITY color_generator;


ARCHITECTURE a OF color_generator IS
	signal data_next  : std_logic_vector(7 downto 0);
	signal data_next_uint : unsigned (7 downto 0);
BEGIN
	data_next <= std_logic_vector(data_next_uint);
	DATA <= data_next;

 
process (reset, increase) is
begin
	if reset = '1' then
		data_next_uint <= (others => '0');
		
	elsif rising_edge (increase) then
		data_next_uint <= data_next_uint + 10;
	
	end if;
		
 end process;

 
END a;