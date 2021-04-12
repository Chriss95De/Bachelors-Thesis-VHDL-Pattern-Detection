-- Design Name	: SYNCHRONIZATION
-- File Name	: SYNCHRONIZATION.vhd
-- Function		: Synchronies asynchon signals
-- Coder			: Lukas Herbst

--								FF1				FF2
--								--------		  	--------
--		signal_async------|in out|-------|in out|------signal_sync
--								|		 |			|		 |
--								|		 |			|		 |	
--						------|>		 |		---|>		 |
--						|		|		 |		|	|		 |
--						|		--------		|	--------
--						|						|
--		clk----------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SYNCHRONIZATION is
port 
(
	clk			: in std_logic;				-- clock for increment
	signal_in	: in std_logic;				--	async signal
	reset			: in std_logic;				-- reset
	signal_out	: out std_logic				-- synchronized signal
);
end entity SYNCHRONIZATION;


architecture a of SYNCHRONIZATION is
	signal signal_in_ff_1	: std_logic;	-- synchronized signal_in -> output signal of flipflop 1
	signal signal_in_ff_2	: std_logic; 	-- synchronized signal_in -> output signal of flipflop 2

begin
	signal_out <= signal_in_ff_2;				-- signal_in_ff_2 to output

process (clk, reset) is
begin
	
	if reset = '1' then							-- reset values
		signal_in_ff_1 <= '0';					-- reset flipflop 1
		signal_in_ff_2 <= '0';					-- reset flipflop 2
			
	elsif rising_edge (clk) then
		signal_in_ff_1 <= signal_in;			-- generate flipflop 1
		signal_in_ff_2 <= signal_in_ff_1;	-- generate flipflop 2
	end if;
		
 end process;

END a;