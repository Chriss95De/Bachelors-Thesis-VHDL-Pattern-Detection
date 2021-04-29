LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
use ieee.math_real.all;


ENTITY xy_to_address IS
GENERIC (
	ADDR_WIDTH		: POSITIVE:= 20;		-- Width of the data line
	RES_WIDTH		: POSITIVE:= 640;		-- Width of the data line
	RES_HEIGHT		: POSITIVE:= 480;		-- Width of the data line
	ADDR_X_WIDTH	: POSITIVE:= 10;		-- Width of the x address line
	ADDR_Y_WIDTH	: POSITIVE:= 9;		-- Width of the y address line
	DATA_BYTES		: POSITIVE:= 2			-- Number of bytes data line
	);
PORT  
(
	X         : in unsigned(ADDR_X_WIDTH-1 DOWNTO 0); 
	Y         : in unsigned(ADDR_Y_WIDTH-1 DOWNTO 0);
	ADDR      : out std_logic_vector(ADDR_WIDTH-1 DOWNTO 0)
);


	
END ENTITY xy_to_address;

ARCHITECTURE a OF xy_to_address IS
BEGIN

	--ADDR <= std_logic_vector(resize(shift_right(unsigned(X),2) + Y*shift_right(to_unsigned(RES_WIDTH,ADDR_X_WIDTH-1),2), ADDR_WIDTH));
	ADDR <= std_logic_vector(resize(shift_right(X,2) + 160*Y, ADDR_WIDTH));

END a;