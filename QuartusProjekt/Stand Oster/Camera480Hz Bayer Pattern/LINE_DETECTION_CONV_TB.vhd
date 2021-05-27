library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- leere entity
entity LINE_DETECTION_CONV_TB is
end entity LINE_DETECTION_CONV_TB;

architecture a of LINE_DETECTION_CONV_TB is

  -- Moduldeklaration
  component LINE_DETECTION_CONV is
    port (	
		clk				: in std_logic;							-- clock
		reset				: in std_logic;							-- reset
	
		-- current center position
		pxl_center_x		: in unsigned(9 downto 0);
		pxl_center_y		: in unsigned(8 downto 0);
	
		-- conv values
		R_conv		: in std_logic_vector(7 downto 0);
		G_conv		: in std_logic_vector(7 downto 0);
		B_conv		: in std_logic_vector(7 downto 0);
		
		-- normal values
		R				: in std_logic_vector(7 downto 0);
		G				: in std_logic_vector(7 downto 0);
		B				: in std_logic_vector(7 downto 0);
	
		--Output
		det_obj_cnt_out		: out unsigned (1 downto 0); 											-- count detected object
		det_obj_x_pos_beg		: out unsigned (9 downto 0);											-- x-pos of beginning object 	-> first black pixel
		det_obj_x_pos_mid		: out unsigned (9 downto 0);											-- x-pos midpoint of object
		det_obj_x_pos_end		: out unsigned (9 downto 0);
		det_obj_conv			: out std_logic_vector (7 downto 0);

		debug_out 				: out unsigned (9 downto 0)
    );
  end component;

  -- input
  signal clk   										: std_logic := '0';
  signal reset 										: std_logic;
  signal pxl_center_x 								: unsigned(9 downto 0) := (others => '0');
  signal pxl_center_y								: unsigned(8 downto 0) := (others => '0');
  signal R_conv, G_conv, B_conv, R, G, B 		: std_logic_vector(7 downto 0) := (others => '0');

  -- output
  signal det_obj_cnt_out															: unsigned (1 downto 0); 											
  signal det_obj_x_pos_beg, det_obj_x_pos_mid, det_obj_x_pos_end		: unsigned (9 downto 0);
  signal det_obj_conv																: std_logic_vector (7 downto 0);
  signal debug_out 																	: unsigned (9 downto 0);
 

begin
  clk   <= not clk  after 10 ns;  -- 25 MHz Taktfrequenz
  reset <= '1', '0' after 5 ns; -- erzeugt Resetsignal: --__
  
  pxl_center_x <= pxl_center_x+1 after 20 ns;
  pxl_center_y <= "011101111";
  
  R_conv <= (others => '0');
  G_conv <= (others => '0');
  B_conv <= (others => '0');
  
  R <= "11001000" after 50 ns; --change to 101 -> avg greyscale should be higher then treshhold 
  G <= "00000101" after 50 ns;
  B <= "00000101" after 50 ns;

  -- Modulinstatziierung
  dut : LINE_DETECTION_CONV
    port map (
		--in
      clk       => clk,
      reset     => reset,

		
		pxl_center_x => pxl_center_x,
		pxl_center_y => pxl_center_y,
		
		R_conv => R_conv,
		G_conv => G_conv,
		B_conv => B_conv,
		
		R => R,
		G => G,
		B => B,
		
		--out
		det_obj_cnt_out => det_obj_cnt_out,
		
		det_obj_x_pos_beg => det_obj_x_pos_beg,
		det_obj_x_pos_mid => det_obj_x_pos_mid,
		det_obj_x_pos_end => det_obj_x_pos_end,
		
		det_obj_conv => det_obj_conv,
		debug_out => debug_out
      );

end architecture;