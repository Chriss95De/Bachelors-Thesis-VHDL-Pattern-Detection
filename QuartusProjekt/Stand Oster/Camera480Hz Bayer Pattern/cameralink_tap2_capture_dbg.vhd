LIBRARY IEEE;
USE IEEE. std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
/*
             __    __    __    __    __    __    __
CLK       __|  |__|  |__|  |__|  |__|  |__|  |__|  
         ______________________           :        
LVAL   _|   :     :     :     :|___________________
            :     :     :     :     :     :        
            : _______________________     :        
lval_dly(0) _|    :     :     :     :|_____________
                  :     :     :     :     :        
                  : _______________________        
lval_dly(1) _______|                      :|_______
                  :     :     :     :     :        
x             old : 0   : 2   : 4   : 6   : 6      
                  :     :     :     :     :        
tap1_1          - : 1st : 2nd : 3rd : 4th : -      
tap2_1          - : 1st : 2nd : 3rd : 4th : -      
                  :     :     :     :     :        
tap1_1, pixel   - : 0   : 2   : 4   : 6   : -      
tap2_1, pixel   - : 1   : 3   : 5   : 7   : -      

*/
ENTITY cameralink_tap2_capture_dbg IS
  generic(NUM_BITS       : positive := 8;
          SAMPLE_SIZE_LD : positive := 6;  -- 6 = 6 bits => mean value calculated using 64 values
          POS_SIZE_LD    : positive := 10);
  PORT  (
        RESET     :  in std_logic;
        CLK       :  in std_logic;
        GO        :  in std_logic;
        POS_X     :  in unsigned(POS_SIZE_LD-1 DOWNTO 0);
        POS_Y     :  in unsigned(POS_SIZE_LD-1 DOWNTO 0);
        TAP1      :  in std_logic_vector(NUM_BITS-1 DOWNTO 0);
        TAP2      :  in std_logic_vector(NUM_BITS-1 DOWNTO 0);
        LVAL      :  in std_logic;
        FVAL      :  in std_logic;
        POS_X_MAX         : out unsigned(POS_SIZE_LD-1 DOWNTO 0);
        POS_Y_MAX         : out unsigned(POS_SIZE_LD-1 DOWNTO 0);
        PIXEL_AT_X_Y      : out std_logic_vector(NUM_BITS-1 DOWNTO 0);
        PIXEL_MEAN_AT_X_Y : out std_logic_vector(NUM_BITS-1 DOWNTO 0);
        CNT_FVAL          : out unsigned(31 DOWNTO 0);
        TGL_DBG           : out std_logic
      );

end entity cameralink_tap2_capture_dbg;

ARCHITECTURE a OF cameralink_tap2_capture_dbg IS
  signal x, y     :  unsigned(POS_SIZE_LD-1 DOWNTO 0);
  signal fval_dly :  std_logic_vector(1 downto 0);
  signal lval_dly :  std_logic_vector(1 downto 0);
  signal tap1_0, tap1_1 : std_logic_vector(NUM_BITS-1 downto 0);
  signal tap2_0, tap2_1 : std_logic_vector(NUM_BITS-1 downto 0);
  signal pixel_sum : unsigned(NUM_BITS+SAMPLE_SIZE_LD-1 downto 0); 
  signal pixel_sum_counter : unsigned(SAMPLE_SIZE_LD-1 downto 0);
begin
------------------------------------------------------------------------------

  process(RESET, CLK)
  begin  
    if RESET = '1' then
      POS_X_MAX     <= (others => '0');
      POS_Y_MAX     <= (others => '0');
      PIXEL_AT_X_Y  <= (others => '0');
      pixel_sum     <= (others => '0');
      pixel_sum_counter <= (others => '0');
      CNT_FVAL          <= (others => '0');
    elsif rising_edge(CLK) then
      fval_dly <= fval_dly(0) & FVAL;
      lval_dly <= lval_dly(0) & LVAL;
      tap1_0 <= TAP1; tap1_1 <= tap1_0;
      tap2_0 <= TAP2; tap2_1 <= tap2_0;
   
      -- Frame counter increments at end of frame
      if fval_dly = "10" then CNT_FVAL <= CNT_FVAL + 1; end if;

      -- y counter incrments at end of line, zero at start of frame
      if lval_dly = "10" then y <= y + 1; end if; -- inc at end of line
      if fval_dly = "01" then y <= (others => '0'); end if; -- zero at start of frame

      -- x counter
      if (fval_dly(0) = '1') and (lval_dly = "11") then x <= x + 2; end if; -- 2-tap -> x+2
      if (fval_dly(0) = '1') and (lval_dly = "01") then x <= (others => '0'); end if; -- zero at start of line

      -- POS_X_MAX, POS_Y_MAX
      if x > POS_X_MAX then POS_X_MAX <= x; end if;
      if y > POS_Y_MAX then POS_Y_MAX <= y; end if;

      -- PIXEL_AT_X_Y
      if GO = '1' then
        if(x(POS_SIZE_LD-1 downto 1) = POS_X(POS_SIZE_LD-1 downto 1)) and (y = POS_Y) then
          if POS_X(0) = '0' then PIXEL_AT_X_Y <= tap1_1;
          else                   PIXEL_AT_X_Y <= tap2_1; end if;
        end if;
      end if;
      
      -- Mean value of PIXEL_AT_X_Y
      if GO = '1' then
        if(x(POS_SIZE_LD-1 downto 1) = POS_X(POS_SIZE_LD-1 downto 1)) and (y = POS_Y) then
          pixel_sum_counter <= pixel_sum_counter + 1;
          
          if POS_X(0) = '0' then
            pixel_sum <= pixel_sum + resize(unsigned(tap1_1), NUM_BITS+SAMPLE_SIZE_LD);
          else  
            pixel_sum <= pixel_sum + resize(unsigned(tap2_1), NUM_BITS+SAMPLE_SIZE_LD);
          end if;
          if pixel_sum_counter = 0 then
            TGL_DBG <= not TGL_DBG;
            PIXEL_MEAN_AT_X_Y <= std_logic_vector(pixel_sum(NUM_BITS+SAMPLE_SIZE_LD-1 downto SAMPLE_SIZE_LD));  -- todo later: rounding
            pixel_sum <= (others => '0');
          end if;
        end if;
      end if;
      
    end if;
  end process;
end a;
