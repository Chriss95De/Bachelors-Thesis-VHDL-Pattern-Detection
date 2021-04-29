LIBRARY ieee;
USE ieee.std_logic_1164.all;

entity seg7dec is port(
  i :         in  std_logic_vector(3 downto 0);
  segments :  out std_logic_vector(0 to 6)
  );
end entity seg7dec;

architecture a of seg7dec is
begin
-- Die einzelnen Segmente serden _nicht_ invertiert!
--  sega <= segments(0);
--  segb <= segments(1);
--  segc <= segments(2);
--  segd <= segments(3);
--  sege <= segments(4);
--  segf <= segments(5);
--  segg <= segments(6);
--      ---a---           ---0---
--     |       |         |       |
--     f       b         5       1
--     |       |         |       |
--      ---g---   bzw.    ---6---
--     |       |         |       |
--     e       c         4       2
--     |       |         |       |
--      ---d---           ---3---
---------------------------------------------------------------------
--      0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F
--      -       -   -       -   -   -   -   -   -       -       -   -
--     | |   |   |   | | | |   |     | | | | | | | |   |     | |   |
--              -   -   -   -   -       -   -   -   -       -   -   -
--     | |   | |     |   |   | | |   | | |   | | | | | |   | | |   |
--      -       -   -       -   -       -   -       -   -   -   -
  with i select
    segments <= "1111110" when "0000",
                "0110000" when "0001", 
                "1101101" when "0010", 
                "1111001" when "0011",  
                "0110011" when "0100", 
                "1011011" when "0101", 
                "1011111" when "0110",
                "1110000" when "0111",  
                "1111111" when "1000",  
                "1111011" when "1001",  
                "1110111" when "1010",
                "0011111" when "1011", 
                "1001110" when "1100", 
                "0111101" when "1101",
                "1001111" when "1110", 
                "1000111" when "1111",
                "0000000" when others;  

end architecture a;