library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
--use ieee.std_logic_arith.all;

-- leere entity
entity OBJECT_DETECTION_TB is
generic (
		MAX_DIFF					: POSITIVE := 20;
		RES_WIDTH				: POSITIVE := 640;		-- Resolution x
		RES_HEIGHT				: POSITIVE := 480;		-- Resolution y

		ADDR_X_WIDTH				: POSITIVE:= 10;	-- Width of the x address line
		ADDR_Y_WIDTH				: POSITIVE:= 9 	-- Width of the y address line
		
		);
end entity OBJECT_DETECTION_TB;

architecture a of OBJECT_DETECTION_TB is

  -- Moduldeklaration
  component OBJECT_DETECTION is
    port (
	 
		clk				: in std_logic;							-- clock
		reset				: in std_logic;							-- reset
		
		det_obj_x_pos_beg		: in unsigned (ADDR_X_WIDTH-1 downto 0);
		det_obj_x_pos_end		: in unsigned (ADDR_X_WIDTH-1 downto 0);
		det_obj_found			: in std_logic;
		
		cur_pos_x				: in unsigned(ADDR_X_WIDTH-1 downto 0);
		cur_pos_y				: in unsigned(ADDR_Y_WIDTH-1 downto 0);
		
		obj_center_x			: out unsigned(ADDR_X_WIDTH-1 downto 0);
		obj_center_y			: out unsigned(ADDR_Y_WIDTH-1 downto 0);

		line_count_deb			: out unsigned(ADDR_Y_WIDTH-1 downto 0)
    );
  end component;

  -- input
  signal clk   											: std_logic := '0';
  signal reset 											: std_logic := '0';
  
  signal det_obj_x_pos_beg, det_obj_x_pos_end 	: unsigned(9 downto 0) := (others => '0');
  signal det_obj_found 			        : std_logic := '0';
  signal cur_pos_x				: unsigned(ADDR_X_WIDTH-1 downto 0) := (others => '0');
  signal cur_pos_y				: unsigned(ADDR_Y_WIDTH-1 downto 0) := (others => '0');

  -- outputcur_pos_y
  
  signal obj_center_x				: unsigned (ADDR_X_WIDTH-1 downto 0);
  signal obj_center_y				: unsigned (ADDR_Y_WIDTH-1 downto 0);

  signal line_count_deb				: unsigned (ADDR_Y_WIDTH-1 downto 0);
 
begin

clk   <= not clk  after 10 ns;  -- 25 MHz Taktfrequenz
reset <= '1', '0' after 5 ns; -- erzeugt Resetsignal: --__



process is
begin

  --first line
  wait for 20 ns;
  det_obj_x_pos_beg <= to_unsigned(200, det_obj_x_pos_beg'length);
  det_obj_x_pos_end <= to_unsigned(250, det_obj_x_pos_end'length);

  wait for 20 ns;
  det_obj_found <= '1';
  
  cur_pos_x <= to_unsigned(250, cur_pos_x'length);
  cur_pos_y <= to_unsigned(50, cur_pos_y'length);
  
  wait for 20 ns;
  cur_pos_x <= cur_pos_x + 1;
  det_obj_found <= '0';
  wait for 10 ns;
  cur_pos_x <= cur_pos_x + 1;
  wait for 10 ns;
  cur_pos_x <= cur_pos_x + 1;
  
  
  --next line
  wait for 10 ns;
  cur_pos_y <= cur_pos_y + 1; --increase line
  cur_pos_x <= to_unsigned(250, cur_pos_x'length);
  
  wait for 40 ns;
  det_obj_found <= '1';
  
  wait for 20 ns;
  cur_pos_x <= cur_pos_x + 1;
  det_obj_found <= '0';
  wait for 10 ns;
  cur_pos_x <= cur_pos_x + 1;
  wait for 10 ns;
  cur_pos_x <= cur_pos_x + 1;
  
  --next line
  wait for 10 ns;
  cur_pos_y <= cur_pos_y + 1; --increase line
  cur_pos_x <= to_unsigned(250, cur_pos_x'length);
  
  wait for 40 ns;
  det_obj_found <= '1';
  
  wait for 20 ns;
  cur_pos_x <= cur_pos_x + 1;
  det_obj_found <= '0';
  wait for 10 ns;
  cur_pos_x <= cur_pos_x + 1;
  wait for 10 ns;
  cur_pos_x <= cur_pos_x + 1;
  det_obj_found <= '0';
  wait for 10 ns;

  wait for 100 ns;
  cur_pos_y <= cur_pos_y + 1; --increase line 
  wait for 100 ns;
  cur_pos_y <= cur_pos_y + 1; --increase line   
  det_obj_found <= '1';  
  
  wait for 20 ns;
  det_obj_found <= '0';  
  wait;
  
end process;
  
  -- Modulinstatziierung
  dut : OBJECT_DETECTION
    port map (
		--in
      clk       => clk,
      reset     => reset,

		
		det_obj_x_pos_beg => det_obj_x_pos_beg,
		det_obj_x_pos_end => det_obj_x_pos_end,
		det_obj_found => det_obj_found,
		cur_pos_x => cur_pos_x,
		cur_pos_y => cur_pos_y,
		
		--out
		obj_center_x => obj_center_x,
		obj_center_y => obj_center_y,
		line_count_deb => line_count_deb
		
      );

end architecture;