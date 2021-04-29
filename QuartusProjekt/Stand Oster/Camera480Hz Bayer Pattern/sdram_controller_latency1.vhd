-- gi 2018-01-27 initially from Altera/Terasic VERILOG SDRAM controller 
--    2018-02-06 Completely new structure, use 2-process main FSM 
--    2018-02-20 Running at 125 MHz, but timing not met for 143 MHz
--               ? - separate state machines for initialization and normal operation 
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.ceil;
use ieee.math_real.floor;
use ieee.math_real.log2;
use ieee.math_real.realmax;

entity sdram_controller_latency1 is
  generic(
--  CMD_BUFFER_DEPTH : positive := 3;
    DATA_WIDTH : positive := 32; -- 32
    DATA_BYTES : positive := 4;  -- 4 x 8 bits
    AZ_ADR_WIDTH  : positive := 25; -- 
    ZS_ADR_WIDTH  : positive := 13;
    ZS_CAS_ADR_WIDTH : positive := 10;
    ZS_BANK_WIDTH : positive := 2;
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
    az_reset         : in std_logic;
    az_clk           : in std_logic;
    az_address       : in std_logic_vector(AZ_ADR_WIDTH-1 downto 0);
    az_byteenable_n  : in std_logic_vector(DATA_BYTES-1 downto 0);
    az_read          : in std_logic;
    za_readdata      : out std_logic_vector(DATA_WIDTH-1 downto 0);
    az_write         : in std_logic;
    az_writedata     : in std_logic_vector(DATA_WIDTH-1 downto 0);
    za_readdatavalid : out std_logic;
    za_waitrequest   : out std_logic;
    zs_addr          : out std_logic_vector(ZS_ADR_WIDTH-1 downto 0);
    zs_ba            : out std_logic_vector(ZS_BANK_WIDTH-1 downto 0);
    zs_cas_n,
    zs_cke,
    zs_cs_n          : out std_logic;
    zs_dq            : inout std_logic_vector(DATA_WIDTH-1 downto 0);
    zs_dqm           : out std_logic_vector(DATA_BYTES-1 downto 0);
    zs_ras_n,
    zs_we_n          : out std_logic;
    DBG_sdr_from_state_error : out std_logic_vector(7 downto 0);
    DBG_sdr_timing_error     : out std_logic_vector(7 downto 0)
  );
end entity sdram_controller_latency1;

architecture a of sdram_controller_latency1 is
  -- Counting: From state x to state y, delta = latency = count >= 1
  -- e.g. consecutive states, delta = latency = 1
  -- Most counters have count_max = delta - 1, but not sdr_cnt_reset2pr which uses tRESET2PRE_width
  -- For delta = latency = 1, no counter is necessary 
  -- For counters which might have a minimal delta of 1, use the REALMAX function to get a width > 0
  -- Small counters: shift registers "unsigned", load to 1..1, shift right
  -- E.g. delta = latency = 3, width 2, load "11", cnt = "11" 1 cycle _after_ CMD,
  --      cnt = "01" 2 cycles after CMD, "00" after 3 cycles
  --      cnt(0) = zero = rdy
  --      cnt(1) = nrly_zero = nrly_rdy                                             
  constant ZS_T_REF_CYCLES : positive := integer(FLOOR(ZS_T_REF/ZS_T_CLK));
  constant M_REFS_WIDTH : positive := integer(CEIL(LOG2(real(ZS_RF_INIT_RF_CYCLES)))); -- _not_ -1

component sdram_model is
  generic(
    ZS_CAS_LATENCY : positive := 3;  
    ZS_RF_INIT_RF_CYCLES : positive := 8;
    ZS_T_CLK        : real := 10.0; -- All time parameters in ns
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
end component sdram_model;

  -- az = signals from application (= non-SDRAM) to core
  -- m  = main state machine signals
  -- zs = SDRAM signals, output signals via output registers
  -- (FF downto CMB) signals:
  -- (CMB) = input of D-FF
  -- (FF)  = output of D-FF          

  signal m_ack_refresh_request : std_logic; --_vector(FF downto CMB);

  -- complete address, full width
  signal az_address_saved : std_logic_vector(AZ_ADR_WIDTH-1 downto 0);
  -- parts of full address
  signal az_address_saved_cas, az_address_cas : std_logic_vector(ZS_CAS_ADR_WIDTH-1 downto 0);
  signal az_address_saved_ras, az_address_ras : std_logic_vector(ZS_ADR_WIDTH-1 downto 0);
  signal az_address_saved_bank, az_address_bank : std_logic_vector(ZS_BANK_WIDTH-1 downto 0);

  signal m_bank_match_cmb : std_logic;
  signal az_byteenable_n_saved : std_logic_vector(DATA_BYTES-1 downto 0);

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
  constant CMD_MRS_I : integer := to_integer(CMD_MRS);
  constant CMD_REF_I : integer := to_integer(CMD_REF);
  constant CMD_PRE_I : integer := to_integer(CMD_PRE); 
  constant CMD_ACT_I : integer := to_integer(CMD_ACT); 
  constant CMD_WR_I  : integer := to_integer(CMD_WR); 
  constant CMD_RD_I  : integer := to_integer(CMD_RD);  
  constant CMD_BST_I : integer := to_integer(CMD_BST); 
  constant CMD_NOP_I : integer := to_integer(CMD_NOP); 

  signal m_zs_cmd : unsigned(3 downto 0);    
  signal m_az_cmd_in_pipeline : std_logic; -- az read/write command is saved but was not processed yet ...

  signal m_cmd_decoded : std_logic_vector(7 downto 0);
  signal m_oe    : std_logic; 
  signal m_pending_cmb : std_logic;

  signal sdr_rdy4cmd_latency1 : std_logic_vector(7 downto 0);
  signal sdr_ready_for_dqmhigh : std_logic;

  signal az_read_writen_saved : std_logic;
  signal m_refs : unsigned(M_REFS_WIDTH-1 downto 0); -- number of refresh cycles during initialization

-- main state machine
  type   m_state_type is (MSTATE_AFTER_RESET, MSTATE_FIRST_REFS, MSTATE_MRS, MSTATE_IDLE_AFTER_MRS_OR_PRE_OR_REF,
                          MSTATE_ACT, MSTATE_RD_AFTER_ACT, MSTATE_WR_AFTER_ACT, MSTATE_WAIT,  
                          MSTATE_PRE_REF_IDLE, MSTATE_REF_IDLE, MSTATE_AFTER_RD_WR);
  signal m_state, m_next : m_state_type;

  signal az_writedata_saved,
         m_zs_wrdata : std_logic_vector(DATA_WIDTH-1 downto 0);

  signal m_r_wn_match_cmb, m_row_match_cmb : std_logic;

  signal rd_valid        : unsigned(ZS_CAS_LATENCY-1 downto 0);
  constant REFRESH_COUNTER_WIDTH : positive := integer(LOG2(real(ZS_T_REF_CYCLES))); -- _not_ -1, _not CEIL()
  signal refresh_counter : unsigned(REFRESH_COUNTER_WIDTH-1 downto 0);
  signal refresh_request : std_logic;

  attribute altera_attribute : string;
  attribute altera_attribute of zs_addr  : signal is "FAST_OUTPUT_REGISTER=ON";
  attribute altera_attribute of zs_ba    : signal is "FAST_OUTPUT_REGISTER=ON";
  attribute altera_attribute of zs_cas_n : signal is "FAST_OUTPUT_REGISTER=ON";
  attribute altera_attribute of zs_cs_n  : signal is "FAST_OUTPUT_REGISTER=ON";
  attribute altera_attribute of zs_dq    : signal is "FAST_INPUT_REGISTER=ON; FAST_OUTPUT_ENABLE_REGISTER=ON; FAST_OUTPUT_REGISTER=ON";
  --attribute altera_attribute of zs_dq    : signal is "FAST_OUTPUT_ENABLE_REGISTER=ON; FAST_OUTPUT_REGISTER=ON"; -- gi
  --attribute altera_attribute of za_readdata : signal is "FAST_INPUT_REGISTER=ON"; -- gi
  attribute altera_attribute of zs_dqm   : signal is "FAST_OUTPUT_REGISTER=ON";
  attribute altera_attribute of zs_ras_n : signal is "FAST_OUTPUT_REGISTER=ON";
  attribute altera_attribute of zs_we_n  : signal is "FAST_OUTPUT_REGISTER=ON";
begin

u_model: component sdram_model 
  generic map(
    ZS_CAS_LATENCY       => ZS_CAS_LATENCY,  
    ZS_RF_INIT_RF_CYCLES => ZS_RF_INIT_RF_CYCLES,
    ZS_T_CLK             => ZS_T_CLK,
    ZS_T_DPL             => ZS_T_DPL,
    ZS_T_MRD             => ZS_T_MRD,
    ZS_T_RAS             => ZS_T_RAS, 
    ZS_T_RC              => ZS_T_RC, 
    ZS_T_RCD             => ZS_T_RCD,
    ZS_T_REF             => ZS_T_REF,
    ZS_T_RESET2PRE       => ZS_T_RESET2PRE, 
    ZS_T_RP              => ZS_T_RP,
    CHECK_ERRORS         => CHECK_ERRORS
  )
  port map(
    clk               => az_clk,
    reset             => az_reset,
    cmd               => std_logic_vector(m_zs_cmd),
    cmd_decoded       => m_cmd_decoded,
    from_state_error  => DBG_sdr_from_state_error,
    rdy4cmd_latency1  => sdr_rdy4cmd_latency1,
    rdy4cmd_cmb       => open,
    ready_for_dqmhigh => sdr_ready_for_dqmhigh,
    timing_error      => DBG_sdr_timing_error
  );

  zs_cs_n  <= m_zs_cmd(3);
  zs_ras_n <= m_zs_cmd(2);
  zs_cas_n <= m_zs_cmd(1);
  zs_we_n  <= m_zs_cmd(0);
  zs_cke <= '1';  
  zs_dq <= m_zs_wrdata when m_oe = '1' else (others => 'Z');
  m_ack_refresh_request <= m_cmd_decoded(CMD_REF_I);

  -- parts of full address
  az_address_cas       <=       az_address(ZS_CAS_ADR_WIDTH-1 downto 0);
  az_address_saved_cas <= az_address_saved(ZS_CAS_ADR_WIDTH-1 downto 0);
  az_address_ras       <=       az_address(AZ_ADR_WIDTH-2 downto ZS_CAS_ADR_WIDTH+1);
  az_address_saved_ras <= az_address_saved(AZ_ADR_WIDTH-2 downto ZS_CAS_ADR_WIDTH+1);
  az_address_bank        <=       az_address(AZ_ADR_WIDTH-1) &       az_address(ZS_CAS_ADR_WIDTH);
  az_address_saved_bank  <= az_address_saved(AZ_ADR_WIDTH-1) & az_address_saved(ZS_CAS_ADR_WIDTH);

  m_bank_match_cmb <= '1' when az_address_saved_bank = az_address_bank else '0';

  m_pending_cmb <= '1' when m_bank_match_cmb and m_row_match_cmb and (az_read or az_write) else '0'; -- TODO r_wn_match _not_ necessary

  m_r_wn_match_cmb <= '1' when (az_read_writen_saved and az_read) or
                               (not az_read_writen_saved and az_write) else '0';

  m_row_match_cmb <= '1' when az_address_saved_ras = az_address_ras else '0';

  -- Refresh/init counter and refresh request signal
  process(az_clk, az_reset) is
  begin 
    if az_reset = '1' then
      refresh_counter <= (others => '1');
      refresh_request <= '0';
    elsif rising_edge(az_clk) then
      if to_integer(refresh_counter) = 0 then
        refresh_counter <= to_unsigned(ZS_T_REF_CYCLES, refresh_counter'length);
      else 
        refresh_counter <= refresh_counter - 1;
      end if;
      -- set refresh_request           : - timer = 0, and m_ack_refresh_request = 0
      -- reset refresh_request         : - m_ack_refresh_request = 1
      if m_ack_refresh_request = '1' then
        refresh_request <= '0';
      elsif to_integer(refresh_counter) = 0 then
        refresh_request <= '1';
      end if;
    end if;
  end process;

  -- *** Main FSM ***
m_process:  process(az_clk, az_reset) is
    variable m_zs_cmd_var : unsigned(3 downto 0);   
    variable m_cmd_decoded_var : std_logic_vector(7 downto 0);
  begin 
    if az_reset = '1' then
      az_address_saved <= (others => '1');
      zs_addr <= (others => '1');      -- old: Initialization: A[10] =1 => Precharge _all_ banks
      zs_ba <= (others => '0');
      az_byteenable_n_saved <= (others => '1');
      m_zs_cmd  <= CMD_NOP; -- for initialization, 200 us NOP or CMD_DESL
      m_cmd_decoded  <= (CMD_NOP_I => '1', others => '0');
      zs_dqm  <= (others => '1');
      m_oe <= '0'; -- Important
      rd_valid <= (others => '0');
      za_readdatavalid <= '0';
      za_readdata <= (others => '0');
      az_read_writen_saved  <= '1'; -- not important 
      m_refs <= to_unsigned(ZS_RF_INIT_RF_CYCLES-1, m_refs'length); -- Important!
      m_state <= MSTATE_AFTER_RESET; -- Important!
      m_zs_wrdata <= (others => '0');
      az_writedata_saved <= (others => '0');
      m_az_cmd_in_pipeline <= '0';
      za_waitrequest <= '1';

    elsif rising_edge(az_clk) then
      -- default fix level
      m_cmd_decoded_var := (CMD_NOP_I => '1', others => '0');

      -- Save read/write commands
      if (az_read or az_write) and  not m_az_cmd_in_pipeline then
        az_address_saved      <= az_address;
        az_byteenable_n_saved <= az_byteenable_n;
        az_read_writen_saved  <= az_read;
        az_writedata_saved    <= az_writedata; -- Don't care whether read or write
                   
        -- remember we have saved 
        m_az_cmd_in_pipeline <= '1'; -- set to 0: - @ reset
                                     --           - @ CMD_RD or CMD_WR
        -- Buffer depth = 1, so block further requests
        za_waitrequest <= '1'; 
      end if;
  
      -- Main FSM : - handle initialization, execute refresh, write and read requests
      --              - set m_state
      --              - set m_cmd_decoded_var()
      --              - handle number of refresh cycles after reset (-> m_refs) 
      --            - initialize za_waitrequest(CMB) to 0 after the initial refresh cycles
      case m_state is
        when MSTATE_AFTER_RESET => -- default CMD: NOP
                    if sdr_rdy4cmd_latency1(CMD_PRE_I) then -- 1st CMD_PRE 
                      m_cmd_decoded_var := (CMD_PRE_I => '1', others => '0');
                      m_state <= MSTATE_WAIT;
                      m_next  <= MSTATE_FIRST_REFS;
                    end if;
                    
        when MSTATE_WAIT => -- wait one cycle, so we can use the non-combinatorial version of sdr_rdy4cmd
                    m_cmd_decoded_var := (CMD_NOP_I => '1', others => '0');
                    m_state <= m_next;
                     
        when MSTATE_FIRST_REFS => -- default CMD: NOP
                    if sdr_rdy4cmd_latency1(CMD_REF_I) then
                      m_state <= MSTATE_WAIT;
                      m_next  <= MSTATE_FIRST_REFS;
                      m_cmd_decoded_var := (CMD_REF_I => '1', others => '0');
                      m_refs <= m_refs - 1;
                      if to_integer(m_refs) = 0 then
                        m_state <= MSTATE_WAIT;
                        m_next  <= MSTATE_MRS;
                      end if;
                    end if; 
                        
        when MSTATE_MRS =>  -- default: NOP                                                               
                    if sdr_rdy4cmd_latency1(CMD_MRS_I) then
                      m_cmd_decoded_var := (CMD_MRS_I => '1', others => '0'); -- mode register set
                      m_state <= MSTATE_WAIT;
                      m_next  <= MSTATE_IDLE_AFTER_MRS_OR_PRE_OR_REF;
                      za_waitrequest <= '0';
                    end if;
  
        when MSTATE_IDLE_AFTER_MRS_OR_PRE_OR_REF => 
                    if refresh_request = '1' then
                      m_cmd_decoded_var := (CMD_NOP_I => '1', others => '0');
                      m_state <= MSTATE_REF_IDLE;
                    elsif m_az_cmd_in_pipeline or az_read or az_write then  
                      m_cmd_decoded_var := (CMD_NOP_I => '1', others => '0');
                      m_state <= MSTATE_ACT; -- TODO for latency reason, initiate command ACT at this point ? 
                                             --      for clock speed reason, do it later
                      -- saving address, r_wn, ben/dqm and wrdata plus setting m_az_cmd_in_pipeline is done separately !
                    else
                      m_cmd_decoded_var := (others => '0'); -- CMD_DESL
                    end if;
  
        when MSTATE_ACT => -- called only by MSTATE_IDLE_AFTER_MRS_OR_PRE_OR_REF _if_ no refresh
                           -- => at least one NOP, so we can use the non-combinatorial version of sdr_rdy4cmd
                    if sdr_rdy4cmd_latency1(CMD_ACT_I) then
                      m_cmd_decoded_var := (CMD_ACT_I => '1', others => '0');
                      if az_read_writen_saved = '1' then
                        m_state <= MSTATE_WAIT;
                        m_next  <= MSTATE_RD_AFTER_ACT;
                      else
                        m_state <= MSTATE_WAIT;
                        m_next  <= MSTATE_WR_AFTER_ACT;
                      end if;
                    end if;
          
        when MSTATE_PRE_REF_IDLE =>
                    if sdr_rdy4cmd_latency1(CMD_PRE_I) then
                      m_cmd_decoded_var := (CMD_PRE_I => '1', others => '0');
                      if refresh_request = '1' then              -- 2018-02-20
                        m_state <= MSTATE_WAIT;
                        m_next  <= MSTATE_REF_IDLE;
                      else
                        m_state <= MSTATE_IDLE_AFTER_MRS_OR_PRE_OR_REF;
                      end if;
                    end if;
  
        when MSTATE_REF_IDLE =>
                    if sdr_rdy4cmd_latency1(CMD_REF_I) then
                      m_cmd_decoded_var := (CMD_REF_I => '1', others => '0');
                      m_state <= MSTATE_IDLE_AFTER_MRS_OR_PRE_OR_REF;
                    end if;
  
        when MSTATE_RD_AFTER_ACT => 
                    if sdr_rdy4cmd_latency1(CMD_RD_I) then
                      m_cmd_decoded_var := (CMD_RD_I => '1', others => '0');
                      m_state <= MSTATE_AFTER_RD_WR;
                    end if;
  
        when MSTATE_WR_AFTER_ACT =>
                    if sdr_rdy4cmd_latency1(CMD_WR_I) then
                      m_cmd_decoded_var := (CMD_WR_I => '1', others => '0');
                      m_state <= MSTATE_AFTER_RD_WR;
                    end if;
  
        when MSTATE_AFTER_RD_WR => -- wait for read or write or refresh, stay active as long as possible
                    -- wr -> rd allowed WO waiting
                    -- rd -> wr allowed after some waiting
                    if refresh_request = '1' then 
                      m_cmd_decoded_var := (CMD_NOP_I => '1', others => '0');
                      m_state <= MSTATE_WAIT;
                      m_next  <= MSTATE_PRE_REF_IDLE;
                    else -- prepare next reading or writing
                      if m_pending_cmb = '1' then -- pending = '1' when bank_match and row_match and (az_read or az_write)
                        if m_r_wn_match_cmb = '1' then 
                          if az_read = '1' then m_cmd_decoded_var := (CMD_RD_I => '1', others => '0');
                          else                  m_cmd_decoded_var := (CMD_WR_I => '1', others => '0');
                          end if;
                        else -- switching rd/wr
                          if az_read = '1' then
                            m_cmd_decoded_var := (CMD_RD_I => '1', others => '0');
                          else
                            m_cmd_decoded_var := (CMD_NOP_I => '1', others => '0');
                            m_state <= MSTATE_WAIT;
                            m_next  <= MSTATE_WR_AFTER_ACT; -- there: wait until writing allowed
                          end if;
                        end if;  
                      else -- no new command, or bank/row not fitting 
                        m_cmd_decoded_var := (CMD_NOP_I => '1', others => '0');
                        if not (az_read or az_write) then -- no new command
                          m_state <= MSTATE_AFTER_RD_WR;  
                        else -- bank/row ... not fitting
                          m_state <= MSTATE_WAIT;
                          m_next  <= MSTATE_PRE_REF_IDLE; -- 2018-02-20
                        end if;
                      end if;
                    end if;
      end case; -- m_state

      -- encode SDRAM commands
      if    m_cmd_decoded_var(CMD_ACT_I) = '1' then m_zs_cmd_var := CMD_ACT;
      elsif m_cmd_decoded_var(CMD_BST_I) = '1' then m_zs_cmd_var := CMD_BST;
      elsif m_cmd_decoded_var(CMD_MRS_I) = '1' then m_zs_cmd_var := CMD_MRS;
      elsif m_cmd_decoded_var(CMD_NOP_I) = '1' then m_zs_cmd_var := CMD_NOP; 
      elsif m_cmd_decoded_var(CMD_PRE_I) = '1' then m_zs_cmd_var := CMD_PRE;
      elsif m_cmd_decoded_var(CMD_RD_I)  = '1' then m_zs_cmd_var := CMD_RD;
      elsif m_cmd_decoded_var(CMD_REF_I) = '1' then m_zs_cmd_var := CMD_REF;
      elsif m_cmd_decoded_var(CMD_WR_I)  = '1' then m_zs_cmd_var := CMD_WR;
      else                                          m_zs_cmd_var := CMD_DESL;
      end if;
  
      -- create FFs
      m_cmd_decoded <= m_cmd_decoded_var;
      m_zs_cmd      <= m_zs_cmd_var;
  
      -- *** SDRAM address ***
      if m_cmd_decoded_var(CMD_PRE_I) or m_cmd_decoded_var(CMD_REF_I) then
        zs_addr <= (others => '1'); -- Precharge or refresh _all_ banks
      elsif m_cmd_decoded_var(CMD_MRS_I) = '1' then   
        -- Mode register
        -- M9     : 0 = programmed burst length
        -- M6..4  : CAS_N latency (2 or 3)
        -- M3     : 0 = burst type is sequential
        -- M2..0  : 0 = 1-word-burst
        zs_addr <= (others => '0');
        zs_addr(5 downto 4) <= std_logic_vector(to_unsigned(ZS_CAS_LATENCY,2));
      elsif m_cmd_decoded_var(CMD_ACT_I) = '1' then
        zs_addr <= az_address_saved_ras; -- address is _always_ saved before CMD_ACT is activated
      else -- m_cmd_decoded_var(to_integer(CMD_RD)) or m_cmd_decoded_var(to_integer(CMD_WR))
           -- or CMD_NOP or CMD_BST
        if m_az_cmd_in_pipeline = '1' then -- m_az_cmd_in_pipeline is set to 0 only @ CMD_RD/CMD_WR or reset  
          zs_addr <= (others => '0'); zs_addr(ZS_CAS_ADR_WIDTH-1 downto 0) <= az_address_saved_cas;
        else
          zs_addr <= (others => '0'); zs_addr(ZS_CAS_ADR_WIDTH-1 downto 0) <= az_address_cas;
        end if;
      end if;

      -- *** SDRAM bank ***
      if m_cmd_decoded_var(CMD_PRE_I) or m_cmd_decoded_var(CMD_REF_I) or m_cmd_decoded_var(CMD_MRS_I) then   
        zs_ba <= (others => '0'); -- important only for CMD_MRS
      else -- CMD_ACT CMD_RD or CMD_WR
           -- (or CMD_NOP or CMD_BST)
        if m_az_cmd_in_pipeline = '1' then -- m_az_cmd_in_pipeline is set to 0 only @ CMD_RD/CMD_WR or reset  
          zs_ba <= az_address_saved_bank;
        else
          zs_ba <= az_address_bank;
        end if;
      end if;

      -- *** SRAM DQM ***
      if m_cmd_decoded_var(CMD_RD_I)  then
        zs_dqm <= (others => '0'); -- no complete description, see below to prolongate DQM because of DQM latency=2 at CMD_RD 
      elsif m_cmd_decoded_var(CMD_WR_I)  then
        if m_az_cmd_in_pipeline = '1' then -- m_az_cmd_in_pipeline is set to 0 only @ CMD_RD/CMD_WR or reset  
          zs_dqm <= az_byteenable_n_saved;
        else
          zs_dqm <= az_byteenable_n;
        end if;
      else
        zs_dqm <= (others => '1'); -- important for ???
      end if;
      -- prolongate DQM
      if sdr_ready_for_dqmhigh = '0' then zs_dqm <= (others => '0'); end if;
  
      -- *** OE ***
      m_oe <= m_cmd_decoded_var(CMD_WR_I);
  
      -- *** rd_valid, za_readdatavalid, za_readdata ***
      rd_valid <= shift_left(rd_valid, 1);
      rd_valid(0) <= m_cmd_decoded(CMD_RD_I);

      za_readdatavalid <= rd_valid(ZS_CAS_LATENCY-1);
      za_readdata <= zs_dq;

      -- *** waitrequest and cmd_in_pipeline
      -- keep 2 different signals just in case ...
      -- waitrequest - is set to 1 @ reset
      --             - holds the _ff value per default
      --             - set it to 0 first time at the end of initialization
      --             - is set to 1 when a az command is saved 
      --             - set it to 0 at CMD_RD / CMD_WR
      if m_cmd_decoded_var(CMD_MRS_I) or m_cmd_decoded_var(CMD_RD_I) or m_cmd_decoded_var(CMD_WR_I) then
        za_waitrequest <= '0'; 
      end if;
      -- cmd_in_pipeline - is set to 0 @ reset
      --                 - holds the _ff value per default
      --                 - is set to 1 when a az command is saved 
      --                 - set it to 0 at CMD_RD / CMD_WR
      if m_cmd_decoded_var(CMD_RD_I) or m_cmd_decoded_var(CMD_WR_I) then
        m_az_cmd_in_pipeline <= '0'; -- allow new command to be saved
      end if;

      -- *** WRData ***
      -- Don't care which command is active
      if m_az_cmd_in_pipeline = '1' then m_zs_wrdata <= az_writedata_saved;
      else                               m_zs_wrdata <= az_writedata;
      end if;
  
    end if;
  end process m_process;

end architecture a;