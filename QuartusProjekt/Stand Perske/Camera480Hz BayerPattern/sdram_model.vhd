-- gi 2018-02-16
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.ceil;
use ieee.math_real.floor;
use ieee.math_real.log2;
use ieee.math_real.realmax;

entity sdram_model is
  generic(
    ZS_CAS_LATENCY : positive := 3;  
    ZS_RF_INIT_RF_CYCLES : positive := 8;
    ZS_T_CLK        : real :=  8.0; -- All time parameters in ns
    ZS_T_DPL        : real := 14.0; -- write -> precharge (close open row) e.g. 14 ns
    ZS_T_MRD        : real := 14.0; -- load mode register -> active e.g. 14 ns
    ZS_T_RAS        : real := 49.0; -- command period act-pre e.g. 49 ns 
    ZS_T_RC         : real := 70.0; -- command period ref-ref or act-act e.g. 70 ns 
    ZS_T_RCD        : real := 20.0; -- active to read/write e.g. 20 ns
    ZS_T_REF        : real := 64000.0/8.192; -- time in ns: 64 ms / 8192
    ZS_T_RESET2PRE  : real := 200000.0;      -- power up and clk stable to 1st PRE 
    ZS_T_RP         : real := 20.0;          -- pre to active e.g. 20 ns
    CHECK_ERRORS    : boolean := true
  );
  port(
    clk, reset        : in std_logic;
    cmd               : in std_logic_vector(3 downto 0);
    cmd_decoded       : in std_logic_vector(7 downto 0);
    from_state_error  : out std_logic_vector(7 downto 0);
    rdy4cmd_latency1  : out std_logic_vector(7 downto 0); -- valid 1 clock cycle after a new SDRAM command
    rdy4cmd_cmb       : out std_logic_vector(7 downto 0);
    ready_for_dqmhigh : out std_logic;
    timing_error      : out std_logic_vector(7 downto 0)
  );
end entity sdram_model;

architecture a of sdram_model is
  -- Counting: From state x to state y, delta = latency = count >= 1
  -- E.g. consecutive states, delta = latency = 1
  -- Most counters have count_max = delta - 1, but not sdr_cnt_reset2pr which uses tRESET2PRE_width
  -- For delta = latency = 1, no counter is necessary 
  -- For counters which might have a minimal delta of 1, use the REALMAX function to get a width > 0
  -- Small counters: shift registers "unsigned", load to 1..1, shift right
  -- E.g. delta = latency = 3, width 2, load "11", cnt = "11" 1 cycle _after_ CMD,
  --      cnt = "01" 2 cycles after CMD, "00" after 3 cycles
  --      cnt(0) = zero = rdy
  --      cnt(1) = nrly_zero = nrly_rdy                                             
  constant ZS_T_DPL_CYCLES       : positive := integer(CEIL(ZS_T_DPL/ZS_T_CLK)); -- write -> precharge (close open row) e.g. 14 ns
  constant ZS_T_RD2DQHIGH_CYCLES : positive := integer(ZS_CAS_LATENCY-1);        -- read->DQ=HIGH->write 
  constant ZS_T_MRD_CYCLES       : positive := integer(CEIL(ZS_T_MRD/ZS_T_CLK)); -- load mode register -> active e.g. 14 ns
  constant ZS_T_RAS_CYCLES       : positive := integer(CEIL(ZS_T_RAS/ZS_T_CLK)); -- command period act-pre e.g. 49 ns 
  constant ZS_T_RC_CYCLES        : positive := integer(CEIL(ZS_T_RC/ZS_T_CLK));  -- command period ref-ref or act-act e.g. 70 ns 
  constant ZS_T_RCD_CYCLES       : positive := integer(CEIL(ZS_T_RCD/ZS_T_CLK)); -- active to read/write e.g. 20 ns
  constant ZS_T_RESET2PRE_CYCLES : positive := integer(CEIL(ZS_T_RESET2PRE/ZS_T_CLK)); -- power up, clk stable to precharge, e.g. 200 us
                                                                                       -- E.g. 200000us/8ns = 25000 cycles
  constant ZS_T_RP_CYCLES        : positive := integer(CEIL(ZS_T_RP/ZS_T_CLK));  -- pre to active e.g. 20 ns

  constant tRD2DQHIGH_width : positive := integer(REALMAX(CEIL(LOG2(REAL(ZS_T_RD2DQHIGH_CYCLES))),1.0)); -- make latency 0 possible 
  constant tRESET2PRE_width : positive := integer(CEIL(LOG2(1.0+ZS_T_RESET2PRE/ZS_T_CLK))); -- EG LOG2(25001) = 15 bit

  -- command = cs_n & ras_n & cas_n & we_n
  constant CMD_DESL : unsigned(3 downto 0) := "1111"; -- device deselect
  constant CMD_MRS  : unsigned(3 downto 0) := "0000"; -- mode register set
  constant CMD_REF  : unsigned(3 downto 0) := "0001"; -- auto-refresh
  constant CMD_PRE  : unsigned(3 downto 0) := "0010"; -- precharge
  constant CMD_ACT  : unsigned(3 downto 0) := "0011"; -- bank activate
  constant CMD_WR   : unsigned(3 downto 0) := "0100"; -- write
  constant CMD_RD   : unsigned(3 downto 0) := "0101"; -- read 
  constant CMD_BST  : unsigned(3 downto 0) := "0110"; -- burst stop
  constant CMD_NOP  : unsigned(3 downto 0) := "0111"; -- nop
  constant CMD_ACT_I : integer := to_integer(CMD_ACT); 
  constant CMD_BST_I : integer := to_integer(CMD_BST); 
  constant CMD_DESL_I : integer := 8; 
  constant CMD_MRS_I : integer := to_integer(CMD_MRS);
  constant CMD_NOP_I : integer := to_integer(CMD_NOP); 
  constant CMD_PRE_I : integer := to_integer(CMD_PRE); 
  constant CMD_RD_I  : integer := to_integer(CMD_RD);  
  constant CMD_REF_I : integer := to_integer(CMD_REF);
  constant CMD_WR_I  : integer := to_integer(CMD_WR); 

--Too slow to encode command at this point :-(
--signal cmd_decoded : std_logic_vector(8 downto 0);
  signal cmd_encoded : unsigned(3 downto 0);

  type   sdr_state_type is (SDRSTATE_INIT, SDRSTATE_ACT, SDRSTATE_REF, SDRSTATE_MRS, SDRSTATE_WRITE,
                            SDRSTATE_READ, SDRSTATE_PRE);
  signal sdr_state : sdr_state_type;
  -- counters : allowed to perform a command?
  --            count = 0 => yes
                                                    
  --      from -> ref    pre      act     read       write <- start timer
  -- to v                                            
  --    ref       rf2xx  pr2acrf  ---     ---        ---
  --              tRC.70 tRP.20                      
  --                                                 
  --    pre       rf2xx  ---      ac2pr   ---        wr2pr
  --                              tRAS.42            tDPL.14
  --                                                 
  --    act       rf2xx  pr2acrf  ac2ac   ???        ???
  --              tRC.70 tRP.20   tRC.70             
  --                                                 
  --    read      ---    ---      ac2rdwr ---        ---
  --                              tRCD.20            
  --                                                 
  --    write     ---    ---      ac2rdwr rd2wr      ---     
  --    ^                         tRCD.20 CL+1 cycle 
  --    | check timer
 
  -- counters by shift registers
  signal   shft_ac2ac        : unsigned(ZS_T_RC_CYCLES-2 downto 0);  -- tRC.70
  signal   shft_ac2pr        : unsigned(ZS_T_RAS_CYCLES-2 downto 0); -- tRAS.49
  signal   shft_ac2rdwr      : unsigned(ZS_T_RCD_CYCLES-2 downto 0); -- tRCD.20
  signal   shft_mrs2acprrf   : unsigned(ZS_T_MRD_CYCLES-2 downto 0); -- tMRD.14
  signal   shft_pr2acrf      : unsigned(ZS_T_RP_CYCLES-2 downto 0);  -- tRP.20
  signal   shft_rd2wr        : unsigned(ZS_CAS_LATENCY+1-2 downto 0);-- CL+1
  signal   shft_rf2acmrsprrf : unsigned(ZS_T_RC_CYCLES-2 downto 0);  -- tRC.70
  signal   shft_wr2pr        : unsigned(ZS_T_DPL_CYCLES-2 downto 0); -- tDPL.14

  -- For CL=2, DQM can be set to 1..1 immedialtely after RD
  -- For CL=3, DQM must be 0..0. 1 cycle after RD, then might be set to 1..1
  -- In order to deal with latency 0, use counter instead of shift register 
  signal   cnt_rd2dqmhigh     : unsigned(tRD2DQHIGH_width-1 downto 0);   -- CL-1
  constant cnt_rd2dqmhigh_max : unsigned(tRD2DQHIGH_width-1 downto 0) := to_unsigned(ZS_CAS_LATENCY-1-1, tRD2DQHIGH_width);

  signal   cnt_reset2pr      : unsigned(tRESET2PRE_width-1 downto 0); -- e.g. 200 us
  constant cnt_reset2pr_max  : unsigned(tRESET2PRE_width-1 downto 0) := to_unsigned(ZS_T_RESET2PRE_CYCLES, tRESET2PRE_width);
  signal   cnt_reset2pr_zero : std_logic;

-- For every possible command whith CSn=0, one element,
-- but CMD_BST not used
--     CMD_NOP used as error from state INIT

-- ***********************************************
  function nearly_finished(shift_reg : unsigned; started : std_logic) return std_logic is 
  -- '1' one clock _before_ finished
  -- Assume: Max. = 1..1, shift right
  -- shift register is started/loaded when started = m_cmd_decoded(cmd_number) = 1
  -- E.g.      latency=2     latency=3
  --      CMD     0             00        <- old value
  --              1             11        <- shift register was loaded, delta t = 1
  --              0             01        delta t = 2
  --              0             00        delta t = 3
  begin
    if started = '1' then return '0'; end if; -- counter/shift reg. will be started => not ready
    if shift_reg'length < 2 then return '1'; end if; -- latency 2 -> length 1 => nearly ready 1 cycle after started/loaded
    return(not shift_reg(shift_reg'right + 1));
  end function nearly_finished;
-- ***********************************************

begin
  cmd_encoded <= unsigned(cmd);
/*
  -- decode SDRAM commands
  --Too slow to encode command at this point :-(
  cmd_decoded(CMD_ACT_I)  <= '1' when cmd_encoded = CMD_ACT  else '0';
  cmd_decoded(CMD_BST_I)  <= '1' when cmd_encoded = CMD_BST  else '0';
  cmd_decoded(CMD_DESL_I) <= '1' when cmd_encoded = CMD_DESL else '0';
  cmd_decoded(CMD_MRS_I)  <= '1' when cmd_encoded = CMD_MRS  else '0';
  cmd_decoded(CMD_NOP_I)  <= '1' when cmd_encoded = CMD_NOP  else '0'; 
  cmd_decoded(CMD_PRE_I)  <= '1' when cmd_encoded = CMD_PRE  else '0';
  cmd_decoded(CMD_RD_I)   <= '1' when cmd_encoded = CMD_RD   else '0';
  cmd_decoded(CMD_REF_I)  <= '1' when cmd_encoded = CMD_REF  else '0';
  cmd_decoded(CMD_WR_I)   <= '1' when cmd_encoded = CMD_WR   else '0';
*/
  --
  rdy4cmd_cmb(CMD_ACT_I) <= rdy4cmd_latency1(CMD_ACT_I) and not cmd_decoded(CMD_ACT_I)
                                                        and not cmd_decoded(CMD_MRS_I)
                                                        and not cmd_decoded(CMD_PRE_I)
                                                        and not cmd_decoded(CMD_REF_I);
  rdy4cmd_cmb(CMD_MRS_I) <= rdy4cmd_latency1(CMD_MRS_I) and not cmd_decoded(CMD_REF_I);
  rdy4cmd_cmb(CMD_PRE_I) <= rdy4cmd_latency1(CMD_PRE_I) and not cmd_decoded(CMD_ACT_I)
                                                        and not cmd_decoded(CMD_MRS_I)
                                                        and not cmd_decoded(CMD_REF_I)
                                                        and not cmd_decoded(CMD_WR_I);
  rdy4cmd_cmb(CMD_RD_I)  <= rdy4cmd_latency1(CMD_RD_I)  and not cmd_decoded(CMD_ACT_I);
  rdy4cmd_cmb(CMD_REF_I) <= rdy4cmd_latency1(CMD_REF_I) and not cmd_decoded(CMD_MRS_I)
                                                        and not cmd_decoded(CMD_PRE_I)
                                                        and not cmd_decoded(CMD_REF_I);
  rdy4cmd_cmb(CMD_WR_I)  <= rdy4cmd_latency1(CMD_WR_I)  and not cmd_decoded(CMD_ACT_I)
                                                        and not cmd_decoded(CMD_RD_I);
  rdy4cmd_cmb(CMD_NOP_I) <= '1';
  rdy4cmd_cmb(CMD_BST_I) <= '0';

  ready_for_dqmhigh <= '1' when (to_integer(cnt_rd2dqmhigh) = 0) and 
                                (cmd_decoded(CMD_RD_I) = '0') else '0';

  -- *** SDRAM model FSM ***
  process(clk, reset) is
  begin 
    if reset = '1' then
      sdr_state <= SDRSTATE_INIT;
      timing_error <= (others => '0');
      from_state_error <= (others => '0');
      rdy4cmd_latency1 <= (others => '0');
      cnt_reset2pr     <= cnt_reset2pr_max; -- !
      cnt_reset2pr_zero <= '0';
    elsif rising_edge(clk) then
      timing_error(CMD_BST_I) <= '0'; -- Burst stop not used, prevent warning
      timing_error(CMD_NOP_I) <= '0'; -- NOP alway allowed, no timing restriction
      from_state_error(CMD_BST_I) <= '0'; -- Burst stop not used, prevent warning

      -- Normal "counting"/shifting
      shft_ac2ac        <= shift_right(shft_ac2ac, 1);
      shft_ac2pr        <= shift_right(shft_ac2pr, 1);
      shft_ac2rdwr      <= shift_right(shft_ac2rdwr, 1);
      shft_mrs2acprrf   <= shift_right(shft_mrs2acprrf, 1);
      shft_pr2acrf      <= shift_right(shft_pr2acrf, 1);
      shft_rd2wr        <= shift_right(shft_rd2wr, 1);
      shft_rf2acmrsprrf <= shift_right(shft_rf2acmrsprrf, 1);
      shft_wr2pr        <= shift_right(shft_wr2pr, 1);
      if cnt_rd2dqmhigh /= to_unsigned(0, cnt_rd2dqmhigh'length) then cnt_rd2dqmhigh <= cnt_rd2dqmhigh - 1; end if; 
      if to_integer(cnt_reset2pr)  = 32 then cnt_reset2pr_zero <= '1'; end if; 
      cnt_reset2pr <= cnt_reset2pr - 1; -- Stopping not required

      -- Loading "counters"/shift registers
      -- No loading of reset2pre counter ;-)
      if cmd_decoded(CMD_ACT_I) = '1' then shft_ac2ac   <= (others => '1'); 
                                           shft_ac2pr   <= (others => '1'); 
                                           shft_ac2rdwr <= (others => '1');      end if;
      if cmd_decoded(CMD_MRS_I) = '1' then shft_mrs2acprrf <= (others => '1');   end if;
      if cmd_decoded(CMD_PRE_I) = '1' then shft_pr2acrf <= (others => '1');      end if;
      if cmd_decoded(CMD_RD_I)  = '1' then shft_rd2wr <= (others => '1');
                                           cnt_rd2dqmhigh <= cnt_rd2dqmhigh_max; end if;
      if cmd_decoded(CMD_REF_I) = '1' then shft_rf2acmrsprrf <= (others => '1'); end if;
      if cmd_decoded(CMD_WR_I)  = '1' then shft_wr2pr <= (others => '1'); end if;

      -- Resulting "ready for executing command"
      rdy4cmd_latency1(CMD_ACT_I) <= nearly_finished(shft_ac2ac, cmd_decoded(CMD_ACT_I)) and 
                                     nearly_finished(shft_mrs2acprrf, cmd_decoded(CMD_MRS_I)) and
                                     nearly_finished(shft_pr2acrf, cmd_decoded(CMD_PRE_I)) and 
                                     nearly_finished(shft_rf2acmrsprrf, cmd_decoded(CMD_REF_I));
      rdy4cmd_latency1(CMD_MRS_I) <= nearly_finished(shft_rf2acmrsprrf, cmd_decoded(CMD_REF_I));
      rdy4cmd_latency1(CMD_PRE_I) <= nearly_finished(shft_ac2pr, cmd_decoded(CMD_ACT_I)) and
                                     nearly_finished(shft_mrs2acprrf, cmd_decoded(CMD_MRS_I)) and
                                     nearly_finished(shft_rf2acmrsprrf, cmd_decoded(CMD_REF_I)) and 
                                     nearly_finished(shft_wr2pr, cmd_decoded(CMD_WR_I)) and
                                     cnt_reset2pr_zero;
      rdy4cmd_latency1(CMD_RD_I)  <= nearly_finished(shft_ac2rdwr, cmd_decoded(CMD_ACT_I));
      rdy4cmd_latency1(CMD_REF_I) <= nearly_finished(shft_mrs2acprrf, cmd_decoded(CMD_MRS_I)) and 
                                     nearly_finished(shft_pr2acrf, cmd_decoded(CMD_PRE_I)) and
                                     nearly_finished(shft_rf2acmrsprrf, cmd_decoded(CMD_REF_I));
      rdy4cmd_latency1(CMD_WR_I)  <= nearly_finished(shft_ac2rdwr, cmd_decoded(CMD_ACT_I)) and
                                     nearly_finished(shft_rd2wr, cmd_decoded(CMD_RD_I));
      rdy4cmd_latency1(CMD_BST_I) <= '0';
      rdy4cmd_latency1(CMD_NOP_I) <= '1';

      if CHECK_ERRORS then
        case sdr_state is
          when SDRSTATE_INIT =>  if (cmd_encoded = CMD_DESL) or (cmd_encoded = CMD_NOP) then
                                                    null;
                                 elsif cmd_encoded = CMD_PRE then
                                                    sdr_state <= SDRSTATE_PRE;
                                                    if cnt_reset2pr_zero /= '1' then timing_error(CMD_PRE_I) <= '1'; from_state_error(7) <= '1'; end if;       
                                 else               from_state_error(7) <= '1'; -- use NOP error for INIT/RESET error
                                 end if;
          when SDRSTATE_ACT =>   if cmd_encoded = CMD_ACT then
                                                    sdr_state <= SDRSTATE_ACT;
                                                    if shft_ac2ac(0) /= '0' then timing_error(CMD_ACT_I) <= '1'; from_state_error(CMD_ACT_I) <= '1'; end if;
                                 elsif (cmd_encoded = CMD_DESL) or (cmd_encoded = CMD_NOP) then
                                                    null;
                                 elsif cmd_encoded = CMD_PRE then sdr_state <= SDRSTATE_PRE;
                                                    if shft_ac2pr(0) /= '0' then timing_error(CMD_PRE_I) <= '1'; from_state_error(CMD_ACT_I) <= '1'; end if;
                                 elsif cmd_encoded = CMD_RD then sdr_state <= SDRSTATE_READ;
                                                    if shft_ac2rdwr(0) /= '0' then timing_error(CMD_RD_I) <= '1'; from_state_error(CMD_ACT_I) <= '1'; end if;
                                 elsif cmd_encoded = CMD_WR then sdr_state <= SDRSTATE_WRITE;
                                                    if shft_ac2rdwr(0) /= '0' then timing_error(CMD_WR_I) <= '1'; from_state_error(CMD_ACT_I) <= '1'; end if;
                                 else               from_state_error(CMD_ACT_I) <= '1';
                                 end if;                                              
          when SDRSTATE_MRS  =>  if cmd_encoded = CMD_ACT then
                                                    sdr_state <= SDRSTATE_ACT;
                                                    if shft_mrs2acprrf(0) /= '0' then timing_error(CMD_ACT_I) <= '1'; from_state_error(CMD_MRS_I) <= '1'; end if;
                                 elsif (cmd_encoded = CMD_DESL) or (cmd_encoded = CMD_NOP) then
                                                    null;
                                 elsif cmd_encoded = CMD_PRE then
                                                    sdr_state <= SDRSTATE_PRE;
                                                    if shft_mrs2acprrf(0) /= '0' then timing_error(CMD_PRE_I) <= '1'; from_state_error(CMD_MRS_I) <= '1'; end if;
                                 elsif cmd_encoded = CMD_REF then
                                                    sdr_state <= SDRSTATE_REF;
                                                    if shft_mrs2acprrf(0) /= '0' then timing_error(CMD_REF_I) <= '1'; from_state_error(CMD_MRS_I) <= '1'; end if;
                                 else               from_state_error(CMD_MRS_I) <= '1';
                                 end if;
          when SDRSTATE_PRE   => if cmd_encoded = CMD_ACT then
                                                    sdr_state <= SDRSTATE_ACT;
                                                    if shft_pr2acrf(0) /= '0' then timing_error(CMD_ACT_I) <= '1'; from_state_error(CMD_PRE_I) <= '1'; end if;
                                 elsif (cmd_encoded = CMD_DESL) or (cmd_encoded = CMD_NOP) then null;
                                 elsif cmd_encoded = CMD_REF then
                                                    sdr_state <= SDRSTATE_REF;
                                                    if shft_pr2acrf(0) /= '0' then timing_error(CMD_REF_I) <= '1'; from_state_error(CMD_PRE_I) <= '1'; end if;
                                 elsif cmd_encoded = CMD_PRE then
                                                    sdr_state <= SDRSTATE_PRE;
                                 else               from_state_error(CMD_PRE_I) <= '1';
                                 end if;
          when SDRSTATE_READ  => if cmd_encoded = CMD_ACT then
                                                    sdr_state <= SDRSTATE_ACT;
                                 elsif (cmd_encoded = CMD_DESL) or (cmd_encoded = CMD_NOP) then
                                                    null;
                                 elsif cmd_encoded = CMD_PRE then
                                                    sdr_state <= SDRSTATE_PRE;
                                 elsif cmd_encoded = CMD_RD then
                                                    sdr_state <= SDRSTATE_READ;
                                 elsif cmd_encoded = CMD_WR then
                                                    sdr_state <= SDRSTATE_WRITE;
                                                    if shft_rd2wr(0) /= '0' then timing_error(CMD_WR_I) <= '1'; from_state_error(CMD_RD_I) <= '1'; end if;
                                 else               from_state_error(CMD_RD_I) <= '1';
                                 end if;
          when SDRSTATE_REF  =>  if cmd_encoded = CMD_ACT then
                                                    sdr_state <= SDRSTATE_ACT;
                                                    if shft_rf2acmrsprrf(0) /= '0' then timing_error(CMD_ACT_I) <= '1'; from_state_error(CMD_REF_I) <= '1';end if;
                                 elsif (cmd_encoded = CMD_DESL) or (cmd_encoded = CMD_NOP) then
                                                    null;
                                 elsif cmd_encoded = CMD_PRE then
                                                    sdr_state <= SDRSTATE_PRE;
                                                    if shft_rf2acmrsprrf(0) /= '0' then timing_error(CMD_PRE_I) <= '1'; from_state_error(CMD_REF_I) <= '1'; end if;
                                 elsif cmd_encoded = CMD_REF then
                                                    sdr_state <= SDRSTATE_REF;
                                                    if shft_rf2acmrsprrf(0) /= '0' then timing_error(CMD_REF_I) <= '1'; from_state_error(CMD_REF_I) <= '1'; end if;
                                 elsif cmd_encoded = CMD_MRS then
                                                    sdr_state <= SDRSTATE_MRS;
                                                    if shft_rf2acmrsprrf(0) /= '0' then timing_error(CMD_MRS_I) <= '1'; from_state_error(CMD_REF_I) <= '1'; end if;
                                 else               from_state_error(CMD_REF_I) <= '1';
                                 end if;
          when SDRSTATE_WRITE => if cmd_encoded = CMD_ACT then
                                                    sdr_state <= SDRSTATE_ACT;
                                 elsif (cmd_encoded = CMD_DESL) or (cmd_encoded = CMD_NOP) then
                                                    null;
                                 elsif cmd_encoded = CMD_PRE then
                                                    sdr_state <= SDRSTATE_PRE;
                                                    if shft_wr2pr(0) /= '0' then timing_error(CMD_PRE_I) <= '1'; from_state_error(CMD_WR_I) <= '1'; end if;
                                 elsif cmd_encoded = CMD_RD then
                                                    sdr_state <= SDRSTATE_READ;
                                 elsif cmd_encoded = CMD_WR then
                                                    sdr_state <= SDRSTATE_WRITE;
                                 else               from_state_error(CMD_WR_I) <= '1';
                                 end if;
        end case;                 
      end if; 
    end if;
  end process; 
end architecture;