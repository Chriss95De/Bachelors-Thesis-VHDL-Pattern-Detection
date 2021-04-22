library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MemoryAccessController is
generic (
	DELAY				: POSITIVE := 16;
	-- Priorities channel 1-8
	PRIO_0			: POSITIVE := 10;
	PRIO_1			: POSITIVE := 10;
	PRIO_2			: POSITIVE := 10;
	PRIO_3			: POSITIVE := 10;
	PRIO_4			: POSITIVE := 10;
	PRIO_5			: POSITIVE := 10;
	PRIO_6			: POSITIVE := 10;
	PRIO_7			: POSITIVE := 10
	);
port (
	clk				: in std_logic;
	reset				: in std_logic;
	-- Req channel 1-8
	req				: in std_logic_vector(7 downto 0);
	-- Act channel 1-8
	act				: in std_logic_vector(7 downto 0);	
	-- Ena channel 1-8
	ena				: out std_logic_vector(7 downto 0)
	);
end entity SDRAM_Read_Buffer_gen;


architecture a of MemoryAccessController is

	signal any_act : std_logic;
	
	-- ein Request muss mind. DELAY Takte anliegen
	signal req_ff	: std_logic_vector(7 downto 0);
	type t_req_del is array (0 to DELAY-1) of std_logic_vector(7 downto 0);
	signal req_del	: t_req_del;	
	signal req_any	: std_logic_vector(7 downto 0);
	
	type t_prio is array (0 to 7) of positive;
	signal prio	: t_prio;
	
	type state_type is (WAIT_REQ, WAIT_ACT, WAIT_ENA);
	signal state 	: state_type;
	
	signal next_req : integer;
	
begin

prio(0) <= PRIO_0;
prio(1) <= PRIO_1;
prio(2) <= PRIO_2;
prio(3) <= PRIO_3;
prio(4) <= PRIO_4;
prio(5) <= PRIO_5;
prio(6) <= PRIO_6;
prio(7) <= PRIO_7;

process(out_pixel_clk, reset) is

	variable req_tmp : std_logic_vector(7 downto 0);	
	variable next_req_tmp : integer;
	variable next_req_prio : integer;
	

	
begin

	if reset = '1' then
	
		for I in 0 to DELAY-1 loop
			req_del(I) <= (other => '0');
		end loop;
		ena <= (other => '0');
		req_ff <= (other => '0');
		req_any <= (other => '0');
		next_req <= 0;
			
	elsif rising_edge(clk) then
	
		req_ff <= req;
		for I in DELAY-1 downto 1 loop		
			req_del(I) <= req_del(I-1);
		end loop;
		req_del(0) <= req_ff;
		
		req_tmp := (others => '0');
		for I in 0 to DELAY-1 loop		
			req_tmp := req_tmp or req_del(I);
		end loop;
		req_any <= req_tmp;
		
		case state is
		
		when WAIT_REQ =>
		
			next_req_prio := 0;
			next_req_tmp := -1;
		
			for I in 0 to 7 loop	
				if (req_any(I) == '1') && (prio(I) > next_req_prio) then
					next_req_tmp := I;
					next_req_prio := prio(I);
				end if;
			end loop;
			
			ena <= (others => '0');
			if (next_req_tmp >= 0) && (req_del(DELAY-1)(next_req_tmp)) then
				ena(next_req_tmp) <= '1';
				state <= WAIT_ACT;
				next_req <= next_req_tmp;
			end if;
		
		when WAIT_ACT =>
		
			ena <= (others => '0');
			ena(next_req) <= '1';		
			if act(next_req) == '1' then
				state <= WAIT_EN;
			end if;
		
		when WAIT_REQ =>	
			ena <= (others => '0');
			if act(next_req) == '0' then
				state <= WAIT_EN;
			end if;
		
		end case;
		
	
	end if;

end architecture a;