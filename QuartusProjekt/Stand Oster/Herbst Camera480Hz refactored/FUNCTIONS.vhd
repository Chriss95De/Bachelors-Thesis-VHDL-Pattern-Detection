-- Design Name	: Function Package
-- File Name	: FUNCTIONS.vhd
-- Function		: Defines functions
-- Coder			: Lukas Herbst

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package func_pack is
	-- to convert std_logic_vector to signed and resize it to resize_length
	function std_to_sig_resize (data_std: std_logic_vector; resize_length: positive) return signed;
end;

package body func_pack is
	function std_to_sig_resize (data_std: std_logic_vector; resize_length: positive) return signed is
		variable sig : signed (9 downto 0);
	begin
		sig 	:=  signed(resize(unsigned(data_std), resize_length));
		return sig;
	end function;
end package body;