-------------------------------------------------------------------------------
--
-- KDF
--
-------------------------------------------------------------------------------
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.slowclk_pkg.all;
use work.TRNG_pkg.all;
use work.sevenseg_pkg.all;

use work.uart_tx_pkg.all;
use work.uart_rx_pkg.all;
--
-------------------------------------------------------------------------------
--
entity rng is

	-- 'LEN' is the generic value of the entity.
	-- 'R2', 'clk_fast', 'reset', 'UART_RX' are the inputs of rng entity.
	-- 'R1', 'X', 'segment7', 'anode' and 'UART_TX' are the outputs of the entity.

	generic(
			LEN : integer := 128 -- Anzahl von Bits, DEFAULT = 128
		);
		
	port (
		R2				 : in std_logic; -- must be assigned to MRCC P (Master), e.g. LOC=H16 #IO_L13P_T2_MRCC_15
		clk_fast 	 : in std_logic;
		reset			 : in std_logic;
		R1				 : out std_logic;
		X				 : out std_logic;
		segment7		 : out std_logic_vector(7 downto 0);
		anode 		 : out std_logic_vector(7 downto 0);
		UART_TX 		 : out std_logic;
		UART_RX  	 : in std_logic;
	);

end rng;
--
-------------------------------------------------------------------------------
--
architecture beh of rng is

	constant CLK_FREQ    : integer := 100E6; -- UART parameter
	constant BAUDRATE    : integer := 9600;  -- UART parameter
	
	-- UART Transmit Signals
	signal rdy_trans : std_logic; 
	signal send_trans, send_trans_next  : std_logic;
	signal data_trans, data_trans_next  : std_logic_vector(7 downto 0);

	-- Output of SlowClock module
	signal clk_slow: std_logic; 
	
	-- Output TRNG module
	signal rndnumb	: std_logic_vector((LEN - 1) downto 0) := (others => '0');
	signal rnd_en: std_logic := '0';
	signal trng_en : std_logic := '0';
	
	-- Random number
	signal rnd_valid : std_logic := '0'; -- Signal for validation of actual random number
	signal rnd_done, rnd_done_next : std_logic := '0'; -- Signal for used random number 
	signal rnd_cpy : std_logic_vector((LEN - 1) downto 0) := (others => '0'); -- Signal for copy of actual random number
	
	-- States:
	type type_state is (
		STATE_IDLE,
		
		);

	signal state, state_next : type_state := STATE_IDLE;
	
begin
	
	slowclk: entity work.slowclk
		port map(
			R2 => R2,
			R1 => R1,
			X => X,			
			clk_slow => clk_slow
		);

	trng: entity work.trng
		generic map(
			LEN => LEN
		)
			
		port map(
			trng_en => trng_en,
			clk_slow => clk_slow,
			clk_fast => clk_fast,
			seed => rndnumb,
			seed_en => rnd_en
		);
		
	sevenseg: entity work.sevenseg
		generic map(
				LEN => LEN 
		)
			
		port map(
			reset => reset,
			rndnumb	=> rnd_cpy,
			clk	=> clk_fast,
			en_new_numb	=> en_7seg,
			segment7 => segment7,
			anode => anode
		);
	
	-- Von Martin Mosbeck
	uart_recv : entity work.uart_rx
		generic map(
			CLK_FREQ => CLK_FREQ,
			BAUDRATE => BAUDRATE
		)

		port map(
			clk      => clk_fast,
			rst      => reset,
			rx       => UART_RX,
			data     => data_recv,
			data_new => data_recv_new
		);
		
	-- Von Martin Mosbeck
	uart_trans : entity work.uart_tx
		generic map(
			CLK_FREQ => CLK_FREQ,
			BAUDRATE => BAUDRATE
		)

		port map(
			clk   => clk_fast,
			rst   => reset,
			send  => send_trans,
			data  => data_trans,
			rdy   => rdy_trans,
			tx    => UART_TX
		);
		
-----------------------------------------------------------------------------
--
-- Process rnd_valid_proc: triggered by clk_fast, rnd_en, rnd_done and rndnumb
-- if new rndnumb is generated, validation flag is set
-- Copy actual random number for later use
--
	rnd_valid_proc: process(clk_fast, rnd_en, rnd_done, rndnumb)
	begin
		if rising_edge(clk_fast) then
			if rnd_en = '1' then
				rnd_valid <= '1';
				if rnd_done = '1' then
					rnd_cpy <= rndnumb;	
				end if;
			else
				rnd_valid <= '0';
			end if;
		end if;
	end process rnd_valid_proc;		

-------------------------------------------------------------------------------
--
-- Process sync_proc: triggered by clk_fast and reset
-- if reset active, resets state maschine, flags and UART communication
-- each clk period states and flags are updated
--
	sync_proc: process (clk_fast, reset)
	begin

		if(reset = '1') then		
			send_trans <= '0';
			data_trans <= (others => '0');
			state      <= STATE_IDLE;
			
		elsif(rising_edge(clk_fast)) then		
			send_trans <= send_trans_next;
			data_trans <= data_trans_next;		
			state      <= state_next;
			en_7seg	  <= en_7seg_next;
			rnd_done	  <= rnd_done_next;

		end if;

	end process sync_proc;

-------------------------------------------------------------------------------
--
-- Process state_out_proc: triggered by state, mode, start_en, send_trans, data_trans, bit_cnt, 
--	run_cnt, en_7seg, test_fin, rnd_done, rnd_valid, rdy_trans, rndnumb and rnd_cpy
-- basic state maschine with IDLE state, state for NIST analyse and state for segment display
--
	state_out_proc: process (state, mode, start_en, send_trans, data_trans, bit_cnt, 
									 run_cnt, en_7seg, test_fin, rnd_done, rnd_valid, 
									 rdy_trans, rndnumb, rnd_cpy)
	begin

		-- prevent latches
		send_trans_next <= send_trans;
		data_trans_next <= data_trans;
		state_next      <= state;
		en_7seg_next	 <= en_7seg;
		rnd_done_next	 <= rnd_done;
		
		case state is

			when STATE_IDLE =>
				-- Reset flags
				en_7seg_next <= '0';
				test_fin_next <= '0';
				bit_cnt_next <= 0;
				run_cnt_next <= 0;
				rnd_done_next <= '1';
				send_trans_next <= '0';
				
				
			when others =>
				null;

		end case;

	end process state_out_proc;
	
end beh;
--
-------------------------------------------------------------------------------