

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; 
library altera_mf;
use altera_mf.altera_mf_components.all;


entity Laplace is
generic (
	Kernel_00	: signed(3 downto 0);
	Kernel_10	: signed(3 downto 0);
	Kernel_20	: signed(3 downto 0);
	Kernel_01	: signed(3 downto 0);
	Kernel_11	: signed(3 downto 0);
	Kernel_21	: signed(3 downto 0);
	Kernel_02	: signed(3 downto 0);
	Kernel_12	: signed(3 downto 0);
	Kernel_22	: signed(3 downto 0)
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
	-- Grayscale
	H_l1					: in std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 1
	H_l2					: in std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 2
	H_l3					: in std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 3
	
	--Output
	R						: out std_logic_vector(7 downto 0);
	G						: out std_logic_vector(7 downto 0);
	B						: out std_logic_vector(7 downto 0);
	H						: out std_logic_vector(7 downto 0)
	 
	); 
end entity Laplace;
	
	
architecture a of Laplace is	
	
	function faltung(l1,l2,l3 : in std_logic_vector(3 * 8 - 1 downto 0)) return std_logic_vector is
		variable sum	: signed(31 downto 0);
	begin
		sum := 0;
		
		sum := sum + Kernel_20*resize(signed(l1(7 downto 0)),32);
		sum := sum + Kernel_10*resize(signed(l1(15 downto 8)),32);
		sum := sum + Kernel_00*resize(signed(l1(23 downto 16)),32);
		sum := sum + Kernel_21*resize(signed(l2(7 downto 0)),32);
		sum := sum + Kernel_11*resize(signed(l2(15 downto 8)),32);
		sum := sum + Kernel_01*resize(signed(l2(23 downto 16)),32);
		sum := sum + Kernel_22*resize(signed(l3(7 downto 0)),32);
		sum := sum + Kernel_12*resize(signed(l3(15 downto 8)),32);
		sum := sum + Kernel_02*resize(signed(l3(23 downto 16)),32);
		
		if sum > 255 then
			sum := 255;
		end if;
		if sum < 0 then
			sum := 0;
		end if;
		
		return std_logic_vector(resize(sum,8)); -- ???
	end function;
begin

R <= faltung(R_l1,R_l2,R_l3);
G <= faltung(G_l1,G_l2,G_l3);
B <= faltung(B_l1,B_l2,B_l3);
H <= faltung(H_l1,H_l2,H_l3);


end architecture a;