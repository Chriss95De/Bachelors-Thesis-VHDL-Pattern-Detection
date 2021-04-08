library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Funktionsweise:
--
-- Eine Zugriffsanfrage wird mittels req angefordert.
-- Bleibt die Anforderung DELAY Takte anstehen, ohne dass eine Anforderung mit höherer Priorität kommt
-- wird ena gesetzt. Darauf muss der Anfordernde Baustein act setzen, solange ein Zugriff erfolgt
-- 
--        __...____
-- req __|         |___...______
--                  ___..._
-- act _____...____|       |____
--                ___
-- ena _____...__|   |_...______
--     _____...__             __
-- rdy           |_____...___|
-- 

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
	
	-- Input memory interface data for each channel
	adr0, adr1, adr2, adr3, adr4, adr5, adr6, adr7 : in std_logic_vector(24 downto 0);	
	dta0, dta1, dta2, dta3, dta4, dta5, dta6, dta7 : in std_logic_vector(31 downto 0);
	rd					: in std_logic_vector(7 downto 0);	
	wr					: in std_logic_vector(7 downto 0);	
		
	-- Ena channel 1-8
	ena				: out std_logic_vector(7 downto 0);
	-- Ready for next access
	rdy				: out std_logic;
		
	-- Multiplex memory interface data for active channel
	mem_adr 			: out std_logic_vector(24 downto 0);	
	mem_dta 			: out std_logic_vector(31 downto 0);
	mem_rd			: out std_logic;	
	mem_wr			: out std_logic
	
	);
end entity MemoryAccessController;


architecture a of MemoryAccessController is

	-- Speichert den aktuell freigegebenen Kanal
	signal act_req : integer;
	
	-- Request Eingangs-FF
	signal req_ff	: std_logic_vector(7 downto 0);
	
	-- Speichert die Takte, die der Request schon anliegt
	type t_req_time is array (0 to 7) of integer;
	signal req_time	: t_req_time;
	-- Speichert, ob ein Signal bereits DELAY Takte anliegt
	signal req_time_exceed	: std_logic_vector(7 downto 0);
		
	-- Speichert die Prioritäten der Anforderungen
	type t_prio is array (0 to 7) of integer;
	signal prio	: t_prio;
	
	-- State machine für Handshake
	type state_type is (WAIT_REQ, WAIT_ACT, WAIT_FINISH);
	signal state 	: state_type;
	
begin


prio(0) <= PRIO_0;
prio(1) <= PRIO_1;
prio(2) <= PRIO_2;
prio(3) <= PRIO_3;
prio(4) <= PRIO_4;
prio(5) <= PRIO_5;
prio(6) <= PRIO_6;
prio(7) <= PRIO_7;


-- Multiplexer

mem_adr <= 	adr0 when act_req=0 else
				adr1 when act_req=1 else
				adr2 when act_req=2 else
				adr3 when act_req=3 else
				adr4 when act_req=4 else
				adr5 when act_req=5 else
				adr6 when act_req=6 else
				adr7 when act_req=7 else
				(others => '0');
mem_dta <= 	dta0 when act_req=0 else
				dta1 when act_req=1 else
				dta2 when act_req=2 else
				dta3 when act_req=3 else
				dta4 when act_req=4 else
				dta5 when act_req=5 else
				dta6 when act_req=6 else
				dta7 when act_req=7 else
				(others => '0');			
mem_rd <= rd(act_req);
mem_wr <= wr(act_req);




process(clk, reset) is

	-- Um den nächsten anstehenden Request zu ermitteln
	variable next_req : integer;
	variable next_req_prio : integer;
	-- Speichert ob ein Baustein schon aktiv ist
	variable any_act : std_logic;

	
begin

	if reset = '1' then
	
		rdy <= '0';
		req_ff <= (others => '0');
		state <= WAIT_REQ;	
		for I in 0 to 7 loop
			req_time(I)	<= 0;
		end loop;
		req_time_exceed <= (others => '0');
		ena <= (others => '0');
			
	elsif rising_edge(clk) then
	
		req_ff <= req;
	
		-- Delay counter für jeden Request erhöhen
		-- Bei Überschreiten von DELAY _exceed bit setzen
		for I in 0 to 7 loop	
			
			if req_ff(I) = '1' and req_time(I) < DELAY then
				req_time(I) <= req_time(I)+1;
				if req_time(I) = DELAY-1 then
					req_time_exceed(I) <= '1';
				end if;
			elsif req_ff(I) = '0' then
				req_time(I) <= 0;
				req_time_exceed(I) <= '0';
			end if;
		end loop;
		
		-- Prüfe welcher anstehende Request höchste Priorität hat
		next_req := -1;
		next_req_prio := -1;		
		for I in 0 to 7 loop
			if req_ff(I) = '1' and prio(I) > next_req_prio then
				next_req := I;
				next_req_prio := prio(I);
			end if;
		end loop;
		
		-- Prüfe ob ein Signal aktiv ist
		any_act := '0';
		for I in 0 to 7 loop
			if act(I) then
				any_act := '1';
			end if;
		end loop;
		
		
		-- Daten zurücksetzen
		ena <= (others => '0');
		rdy <= '0';
		
		
		case state is
		
		-- Warte auf Request
		when WAIT_REQ =>			
		
			if any_act = '0' then
				rdy <= '1';
			end if;
		
			-- Prüfe ob nächster Request schon DELAY Takte ansteht
			-- und kein Baustein mehr activ ist
			if next_req >= 0 and any_act = '0' then
				if req_time_exceed(next_req) = '1' then
					-- Nächste Request freigeben
					state <= WAIT_ACT;
					act_req <= next_req;
					ena(next_req) <= '1';
				end if;
			end if;
		
		
		-- Warte bis act gesetzt wurde
		when WAIT_ACT =>
		
			ena(act_req) <= '1';	
			 
			if act(act_req) = '1' then
				state <= WAIT_FINISH;
			end if;
		 
		
		-- Warte bis act zurückgesetzt wurde
		when WAIT_FINISH =>
			if act(act_req) = '0' then
				state <= WAIT_REQ;
			end if;		
		end case;
		
	
	end if;
	
end process;

end architecture a;