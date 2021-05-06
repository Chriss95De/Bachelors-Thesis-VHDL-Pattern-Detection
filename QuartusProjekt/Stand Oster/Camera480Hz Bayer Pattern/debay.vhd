

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; 
library altera_mf;
use altera_mf.altera_mf_components.all;




--   0,0    1,0    2,0    3,0
--  GBGBG  BGBGB  GBGBG  BGBGB
--  RGRGR  GRGRG  RGRGR  GRGRG
--  GBGBG  BGBGB  GBGBG  BGBGB  ...
--  RGRGR  GRGRG  RGRGR  GRGRG
--  GBGBG  BGBGB  GBGBG  BGBGB
-- 
--   0,1    1,1    2,1    3,1
--  RGRGR  GRGRG  RGRGR  GRGRG
--  GBGBG  BGBGB  GBGBG  BGBGB 
--  RGRGR  GRGRG  RGRGR  GRGRG ...
--  GBGBG  BGBGB  GBGBG  BGBGB 
--  RGRGR  GRGRG  RGRGR  GRGRG
--  
--   0,2    1,2    2,2    3,2
--  GBGBG  BGBGB  GBGBG  BGBGB
--  RGRGR  GRGRG  RGRGR  GRGRG 
--  GBGBG  BGBGB  GBGBG  BGBGB ...
--  RGRGR  GRGRG  RGRGR  GRGRG 
--  GBGBG  BGBGB  GBGBG  BGBGB
-- 
--   0,3    1,3    2,3    3,3
--  RGRGR  GRGRG  RGRGR  GRGRG
--  GBGBG  BGBGB  GBGBG  BGBGB
--  RGRGR  GRGRG  RGRGR  GRGRG ...
--  GBGBG  BGBGB  GBGBG  BGBGB
--  RGRGR  GRGRG  RGRGR  GRGRG
--   ...    ...    ...    ...




entity Debay is
generic (
	ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
	ADDR_Y_WIDTH				: POSITIVE:= 9 	-- Width of the y address line
	);
port (	

	en		: in std_logic;
	
	-- current center position
	pxl_center_x		: in unsigned(ADDR_X_WIDTH-1 downto 0);
	pxl_center_y		: in unsigned(ADDR_Y_WIDTH-1 downto 0);	

	-- Pixel data
	pxl_data_l1			: in std_logic_vector(5 * 8 - 1 downto 0);	-- Pixel data line 1 *** First pixel at 7..0, Highest pixel at 39..32
	pxl_data_l2			: in std_logic_vector(5 * 8 - 1 downto 0);	-- Pixel data line 2
	pxl_data_l3			: in std_logic_vector(5 * 8 - 1 downto 0);	-- Pixel data line 3
	pxl_data_l4			: in std_logic_vector(5 * 8 - 1 downto 0);	-- Pixel data line 4
	pxl_data_l5			: in std_logic_vector(5 * 8 - 1 downto 0);	-- Pixel data line 5

	-- Debay data
	
	-- Red
	R_l1					: out std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 1 *** First pixel at 7..0, Highest pixel at 39..32
	R_l2					: out std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 2
	R_l3					: out std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 3
	-- Green
	G_l1					: out std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 1 *** First pixel at 7..0, Highest pixel at 39..32
	G_l2					: out std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 2
	G_l3					: out std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 3
	-- Blue
	B_l1					: out std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 1 *** First pixel at 7..0, Highest pixel at 39..32
	B_l2					: out std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 2
	B_l3					: out std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 3
	-- Grayscale
	H_l1					: out std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 1 *** First pixel at 7..0, Highest pixel at 39..32
	H_l2					: out std_logic_vector(3 * 8 - 1 downto 0);	-- Pixel data line 2
	H_l3					: out std_logic_vector(3 * 8 - 1 downto 0)	-- Pixel data line 3
	 
	); 
end entity Debay;
	
	
architecture a of Debay is	
	signal XYE		: std_logic_vector(2 downto 0);
	
	-- l1 : C V C
	-- l2 : H M H
	-- l3 : C V C
	
	-- Get average of C values
	function get_c(l1,l2,l3 : in std_logic_vector(3 * 8 - 1 downto 0)) return std_logic_vector is
		variable sum	: unsigned(9 downto 0);
	begin
		sum := 	resize(unsigned(l1(7 downto 0)), 10)+
					resize(unsigned(l1(23 downto 16)), 10)+
					resize(unsigned(l3(7 downto 0)), 10)+
					resize(unsigned(l3(23 downto 16)), 10);
		return std_logic_vector(resize(shift_right(sum, 2),8));
	end function;
	-- Get average of H+V values
	function get_hv(l1,l2,l3 : in std_logic_vector(3 * 8 - 1 downto 0)) return std_logic_vector is
		variable sum	: unsigned(9 downto 0);
	begin
		sum := 	resize(unsigned(l1(15 downto 8)), 10)+
					resize(unsigned(l2(23 downto 16)), 10)+
					resize(unsigned(l2(7 downto 0)), 10)+
					resize(unsigned(l3(15 downto 8)), 10);
		return std_logic_vector(resize(shift_right(sum, 2),8));
	end function;
	-- Get average of H values
	function get_h(l1,l2,l3 : in std_logic_vector(3 * 8 - 1 downto 0)) return std_logic_vector is
		variable sum	: unsigned(8 downto 0);
	begin
		sum := 	resize(unsigned(l2(7 downto 0)), 9)+
					resize(unsigned(l2(23 downto 16)), 9);
		return std_logic_vector(resize(shift_right(sum, 1),8));
	end function;
	-- Get average of V values
	function get_v(l1,l2,l3 : in std_logic_vector(3 * 8 - 1 downto 0)) return std_logic_vector is
		variable sum	: unsigned(8 downto 0);
	begin
		sum := 	resize(unsigned(l1(15 downto 8)), 9)+
					resize(unsigned(l3(15 downto 8)), 9);
		return std_logic_vector(resize(shift_right(sum, 1),8));
	end function;
	-- Get M value
	function get_m(l1,l2,l3 : in std_logic_vector(3 * 8 - 1 downto 0)) return std_logic_vector is
	begin
		return l2(15 downto 8);
	end function;
begin

XYE(0) <= pxl_center_x(0);
XYE(1) <= pxl_center_y(0);
XYE(2) <= en;

-- Line 1

with XYE select R_l1(7 downto 0) <=                                                      -- EYX
	get_h(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0))  when "100",
	get_c(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0))  when "110",
	get_m(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0))  when "101",
	get_v(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0))  when "111",
	get_m(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0))  when others;
with XYE select G_l1(7 downto 0) <=
	get_c(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0))  when "100",
	get_hv(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0)) when "110",
	get_hv(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0)) when "101",
	get_c(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0))  when "111",
	get_m(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0))  when others;
with XYE select B_l1(7 downto 0) <=
	get_v(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0))  when "100",
	get_m(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0))  when "110",
	get_c(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0))  when "101",
	get_h(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0))  when "111",
	get_m(pxl_data_l1(23 downto 0),pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0))  when others;

with XYE select R_l1(15 downto 8) <=                                                     -- EYX
	get_m(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8))  when "100",
	get_v(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8))  when "110",
	get_h(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8))  when "101",
	get_c(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8))  when "111",
	get_m(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8))  when others;
with XYE select G_l1(15 downto 8) <=
	get_hv(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8)) when "100",
	get_c(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8))  when "110",
	get_c(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8))  when "101",
	get_hv(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8)) when "111",
	get_m(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8))  when others;
with XYE select B_l1(15 downto 8) <=
	get_c(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8))  when "100",
	get_h(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8))  when "110",
	get_v(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8))  when "101",
	get_m(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8))  when "111",
	get_m(pxl_data_l1(31 downto 8),pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8))  when others;
	
with XYE select R_l1(23 downto 16) <=                                                       -- EYX
	get_h(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16))  when "100",
	get_c(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16))  when "110",
	get_m(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16))  when "101",
	get_v(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16))  when "111",
	get_m(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16))  when others;
with XYE select G_l1(23 downto 16) <=
	get_c(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16))   when "100",
	get_hv(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16)) when "110",
	get_hv(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16)) when "101",
	get_c(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16))  when "111",
	get_m(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16))  when others;
with XYE select B_l1(23 downto 16) <=
	get_v(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16))  when "100",
	get_m(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16))  when "110",
	get_c(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16))  when "101",
	get_h(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16))  when "111",
	get_m(pxl_data_l1(39 downto 16),pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16))  when others;

-- Line 2

with XYE select R_l2(7 downto 0) <=                                                      -- EYX
	get_c(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0))  when "100",
	get_h(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0))  when "110",
	get_v(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0))  when "101",
	get_m(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0))  when "111",
	get_m(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0))  when others;
with XYE select G_l2(7 downto 0) <=
	get_hv(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0)) when "100",
	get_c(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0))  when "110",
	get_c(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0))  when "101",
	get_hv(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0)) when "111",
	get_m(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0))  when others;
with XYE select B_l2(7 downto 0) <=
	get_m(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0))  when "100",
	get_v(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0))  when "110",
	get_h(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0))  when "101",
	get_c(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0))  when "111",
	get_m(pxl_data_l2(23 downto 0),pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0))  when others;

with XYE select R_l2(15 downto 8) <=                                                     -- EYX
	get_v(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8))  when "100",
	get_m(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8))  when "110",
	get_c(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8))  when "101",
	get_h(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8))  when "111",
	get_m(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8))  when others;
with XYE select G_l2(15 downto 8) <=
	get_c(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8))  when "100",
	get_hv(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8)) when "110",
	get_hv(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8)) when "101",
	get_c(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8))  when "111",
	get_m(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8))  when others;
with XYE select B_l2(15 downto 8) <=
	get_h(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8))  when "100",
	get_c(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8))  when "110",
	get_m(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8))  when "101",
	get_v(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8))  when "111",
	get_m(pxl_data_l2(31 downto 8),pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8))  when others;
	
with XYE select R_l2(23 downto 16) <=                                                       -- EYX
	get_c(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when "100",
	get_h(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when "110",
	get_v(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when "101",
	get_m(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when "111",
	get_m(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when others;
with XYE select G_l2(23 downto 16) <=
	get_hv(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when "100",
	get_c(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when "110",
	get_c(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when "101",
	get_hv(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16)) when "111",
	get_m(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when others;
with XYE select B_l2(23 downto 16) <=
	get_m(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when "100",
	get_v(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when "110",
	get_h(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when "101",
	get_c(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when "111",
	get_m(pxl_data_l2(39 downto 16),pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16))  when others;
	
-- Line 2

with XYE select R_l3(7 downto 0) <=                                                      -- EYX
	get_h(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0))  when "100",
	get_c(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0))  when "110",
	get_m(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0))  when "101",
	get_v(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0))  when "111",
	get_m(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0))  when others;
with XYE select G_l3(7 downto 0) <=
	get_c(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0))  when "100",
	get_hv(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0)) when "110",
	get_hv(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0)) when "101",
	get_c(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0))  when "111",
	get_m(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0))  when others;
with XYE select B_l3(7 downto 0) <=
	get_v(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0))  when "100",
	get_m(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0))  when "110",
	get_c(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0))  when "101",
	get_h(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0))  when "111",
	get_m(pxl_data_l3(23 downto 0),pxl_data_l4(23 downto 0),pxl_data_l5(23 downto 0))  when others;

with XYE select R_l3(15 downto 8) <=                                                     -- EYX
	get_m(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8))  when "100",
	get_v(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8))  when "110",
	get_h(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8))  when "101",
	get_c(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8))  when "111",
	get_m(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8))  when others;
with XYE select G_l3(15 downto 8) <=
	get_hv(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8)) when "100",
	get_c(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8))  when "110",
	get_c(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8))  when "101",
	get_hv(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8)) when "111",
	get_m(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8))  when others;
with XYE select B_l3(15 downto 8) <=
	get_c(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8))  when "100",
	get_h(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8))  when "110",
	get_v(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8))  when "101",
	get_m(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8))  when "111",
	get_m(pxl_data_l3(31 downto 8),pxl_data_l4(31 downto 8),pxl_data_l5(31 downto 8))  when others;
	
with XYE select R_l3(23 downto 16) <=                                                       -- EYX
	get_h(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16))  when "100",
	get_c(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16))  when "110",
	get_m(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16))  when "101",
	get_v(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16))  when "111",
	get_m(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16))  when others;
with XYE select G_l3(23 downto 16) <=
	get_c(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16))   when "100",
	get_hv(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16)) when "110",
	get_hv(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16)) when "101",
	get_c(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16))  when "111",
	get_m(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16))  when others;
with XYE select B_l3(23 downto 16) <=
	get_v(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16))  when "100",
	get_m(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16))  when "110",
	get_c(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16))  when "101",
	get_h(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16))  when "111",
	get_m(pxl_data_l3(39 downto 16),pxl_data_l4(39 downto 16),pxl_data_l5(39 downto 16))  when others;


end architecture a;