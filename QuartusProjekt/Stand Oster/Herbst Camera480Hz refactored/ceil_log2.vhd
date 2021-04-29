LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

package ceil_log2 is
	function log2(i : natural) return integer;
end package ceil_log2;

package body ceil_log2 is
	function log2( i : natural) return integer is
		variable temp    : integer := i;
		variable ret_val : integer := 0; 
	begin					
		while temp > 1 loop
			ret_val := ret_val + 1;
			temp    := temp / 2;     
		end loop;
		return ret_val;
	end function;
end package body ceil_log2;