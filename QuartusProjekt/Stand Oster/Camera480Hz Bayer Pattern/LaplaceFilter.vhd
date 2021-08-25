

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; 
library altera_mf;
use altera_mf.altera_mf_components.all;


entity LaplaceFilter is 
generic (
	Kernel_00	: integer := -1;
	Kernel_10	: integer := -2;
	Kernel_20	: integer := -1;
	Kernel_01	: integer := -2;
	Kernel_11	: integer := 12;
	Kernel_21	: integer := -2;
	Kernel_02	: integer := -1;
	Kernel_12	: integer := -2;
	Kernel_22	: integer := -1
	);
port (	

	en		: in std_logic;

	-- Red
	R_l1					: in std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 1
	R_l2					: in std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 2
	R_l3					: in std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 3
	-- Green
	G_l1					: in std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 1
	G_l2					: in std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 2
	G_l3					: in std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 3
	-- in
	B_l1					: in std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 1
	B_l2					: in std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 2
	B_l3					: in std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 3
	
	--Output
	R						: out std_logic_vector(7 downto 0);
	G						: out std_logic_vector(7 downto 0);
	B						: out std_logic_vector(7 downto 0)
	 
	); 
end entity LaplaceFilter;
	
	
architecture a of LaplaceFilter is	
	
	function convolute(l1,l2,l3 : in std_logic_vector(3 * 8 - 1 downto 0)) return std_logic_vector is
		variable sum	: signed(31 downto 0);
	begin
		sum := (others => '0');
		
		sum := sum + resize(to_signed(Kernel_20,5)	*	signed('0' & l1(7 downto 0))	,32);
		sum := sum + resize(to_signed(Kernel_10,5)	*	signed('0' & l1(15 downto 8))	,32);
		sum := sum + resize(to_signed(Kernel_00,5)	*	signed('0' & l1(23 downto 16))	,32);
		sum := sum + resize(to_signed(Kernel_21,5)	*	signed('0' & l2(7 downto 0))	,32);
		sum := sum + resize(to_signed(Kernel_11,5)	*	signed('0' & l2(15 downto 8))	,32);
		sum := sum + resize(to_signed(Kernel_01,5)	*	signed('0' & l2(23 downto 16))	,32);
		sum := sum + resize(to_signed(Kernel_22,5)	*	signed('0' & l3(7 downto 0))	,32);
		sum := sum + resize(to_signed(Kernel_12,5)	*	signed('0' & l3(15 downto 8))	,32);
		sum := sum + resize(to_signed(Kernel_02,5)	*	signed('0' & l3(23 downto 16))	,32);
		
		sum := shift_right(sum,1);
 		sum := sum+128;
		
		if sum > 255 then
			sum := (others => '1');
		elsif sum < 0 then
			sum := (others => '0');
		end if;
		
		return std_logic_vector(sum(7 downto 0)); -- ???
	end function;
begin

with en select R <=
	convolute(R_l1,R_l2,R_l3)  when '1',
	R_l2(15 downto 8)  			when others;
with en select G <=
	convolute(G_l1,G_l2,G_l3) 	when '1',
	G_l2(15 downto 8)  			when others;
with en select B <=
	convolute(B_l1,B_l2,B_l3)  when '1',
	B_l2(15 downto 8)  			when others;

end architecture a;