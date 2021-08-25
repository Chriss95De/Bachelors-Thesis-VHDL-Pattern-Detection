library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- leere entity
entity LINE_DETECTION_TB is
generic (
		NUMBERS_OF_OBJECTS	: POSITIVE := 3;		-- number of lines / objects, that can be detected
		--THRESHOLD				: POSITIVE := 80;	-- threshold for object-detection
		RES_WIDTH				: POSITIVE := 640;		-- Resolution x
		RES_HEIGHT				: POSITIVE := 480;		-- Resolution y

		ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
		ADDR_Y_WIDTH				: POSITIVE:= 9 	-- Width of the y address line
		
		);
end entity LINE_DETECTION_TB;

architecture a of LINE_DETECTION_TB is

  -- Moduldeklaration
  component LINE_DETECTION is
    port (
	 
		clk				: in std_logic;							-- clock
		reset				: in std_logic;							-- reset
	
		-- current center position
		pxl_pos_x		: in unsigned(9 downto 0);
		pxl_pos_y		: in unsigned(8 downto 0);
	
		-- normal values
		R				: in std_logic_vector(7 downto 0);
		G				: in std_logic_vector(7 downto 0);
		B				: in std_logic_vector(7 downto 0);
		
		threshold 	: in unsigned(7 downto 0);
		
		pixel_data_valid : in std_logic;
	
		--Output
		det_obj_x_pos_beg		: out unsigned (9 downto 0);											
		det_obj_x_pos_end		: out unsigned (9 downto 0);
		det_obj_conv			: out std_logic_vector (7 downto 0);
		det_obj_found			: out std_logic;
		
		cur_pxl_pos_x			: out unsigned(ADDR_X_WIDTH-1 downto 0);
		cur_pxl_pos_y			: out unsigned(ADDR_Y_WIDTH-1 downto 0);

		debug_out 				: out std_logic_vector (7 downto 0)
    );
  end component;

  -- input
  signal clk   										: std_logic := '0';
  signal reset 										: std_logic;
  signal pxl_pos_x 								: unsigned(9 downto 0) := (others => '0');
  signal pxl_pos_y								: unsigned(8 downto 0) := (others => '0');
  signal R, G, B 										: std_logic_vector(7 downto 0) := (others => '0');
  
  signal threshold								: unsigned(7 downto 0) := "01010000";
  
  signal pixel_data_valid						: std_logic := '1';

  -- output											
  signal det_obj_x_pos_beg, det_obj_x_pos_end						: unsigned (9 downto 0);
  signal det_obj_conv														: std_logic_vector (7 downto 0);
  signal det_obj_found														: std_logic;
  
  signal cur_pxl_pos_x														: unsigned(ADDR_X_WIDTH-1 downto 0);
  signal cur_pxl_pos_y														: unsigned(ADDR_Y_WIDTH-1 downto 0);
  
  signal debug_out 															: std_logic_vector (7 downto 0);
 
begin

clk   <= not clk  after 10 ns;  -- 25 MHz Taktfrequenz
reset <= '1', '0' after 5 ns; -- erzeugt Resetsignal: --__

pxl_pos_x <= pxl_pos_x+1 after 20 ns;

process is
begin

  
 
  
  pxl_pos_y <= "011101111";
  
  wait for 50 ns;
  --pxl_pos_x <= pxl_pos_x+1;
  R <= "11001000";
  G <= "00000101";
  B <= "00000101";
  
  wait for 50 ns;
  R <= "00000000";
  G <= "00000101";
  B <= "00000101";
  
  wait for 20 ns;
  pxl_pos_y <= pxl_pos_y+1;

  wait for 30 ns;
  --pxl_pos_x <= (others => '0');
  R <= "11001000";
  G <= "00000101";
  B <= "00000101";
  
  wait for 50 ns;
  --pxl_pos_x <= pxl_pos_x+1;
  R <= "00000000"; 
  G <= "00000101";
  B <= "00000101";
  
  wait for 20 ns;
  pxl_pos_y <= pxl_pos_y+1;
	
  wait for 30 ns;
  R <= "11001000";
  G <= "00000101";
  B <= "00000101";
  
  wait for 50 ns;
  --pxl_pos_x <= (others => '0');
  R <= "00000000"; 
  G <= "00000101";
  B <= "00000101";
  
  wait for 20 ns;
  pxl_pos_y <= pxl_pos_y+1;
  
  wait;
  
end process;
  
  -- Modulinstatziierung
  dut : LINE_DETECTION
    port map (
		--in
      clk       => clk,
      reset     => reset,

		
		pxl_pos_x => pxl_pos_x,
		pxl_pos_y => pxl_pos_y,
		
		R => R,
		G => G,
		B => B,
		
		threshold => threshold,
		
		pixel_data_valid => pixel_data_valid,
		
		--out
		det_obj_x_pos_beg => det_obj_x_pos_beg,
		det_obj_x_pos_end => det_obj_x_pos_end,
		det_obj_found => det_obj_found,
		
		
		cur_pxl_pos_x => cur_pxl_pos_x,
		cur_pxl_pos_y => cur_pxl_pos_y,
		
		det_obj_conv => det_obj_conv,
		debug_out => debug_out
      );

end architecture;