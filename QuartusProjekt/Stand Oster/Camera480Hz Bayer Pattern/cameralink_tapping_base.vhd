LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.numeric_std.ALL;

entity cameralink_tapping_base is
  generic(NUM_TAPS : positive := 2;  -- 2 or 3
          NUM_BITS : positive := 8); -- 8, 10 or 12
  port(
    TX_RX : in  std_logic_vector(0 to 27);
    LVAL  : out std_logic;
    FVAL  : out std_logic;
    DVAL  : out std_logic;
    A     : out std_logic_vector(0 to NUM_BITS-1);
    B     : out std_logic_vector(0 to NUM_BITS-1);
    C     : out std_logic_vector(0 to NUM_BITS-1)
  );
end entity cameralink_tapping_base;

architecture a of cameralink_tapping_base is
  signal port_a, port_b, port_c : std_logic_vector(0 to 7);
begin

  LVAL <= TX_RX(24);
  FVAL <= TX_RX(25);
  DVAL <= TX_RX(26);

  port_a <= TX_RX(0 to 4) & TX_RX(6)        & TX_RX(27)       & TX_RX(5);
  port_b <= TX_RX(7 to 9) & TX_RX(12 to 14) & TX_RX(10 to 11);
  port_c <= TX_RX(15)     & TX_RX(18 to 22) & TX_RX(16 to 17);

  process(all)
  begin

    A <= (others => '0');
    B <= (others => '0');
    C <= (others => '0');

    if NUM_TAPS = 2 then
      if NUM_BITS = 8 then
        A <= port_a;
        B <= port_b;
      elsif NUM_BITS = 10 then
        A <= port_a & port_b(0 to 1);
        B <= port_c & port_b(4 to 5);
      elsif NUM_BITS = 12 then
        A <= port_a & port_b(0 to 3);
        B <= port_c & port_b(4 to 7);
      end if;
    elsif NUM_TAPS = 3 then
        A <= port_a;
        B <= port_b;
        C <= port_c;
    end if; 
  end process;
end architecture a;
