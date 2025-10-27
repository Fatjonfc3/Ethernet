library IEEE;

use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;


entity ethernet_fsm is
generic ( 
	DATA_IN_WIDTH : integer := 8;
	PREAMBLE_BYTE_LENGTH : integer := 7;
	SFD_BYTE_LENGTH : integer := 1;
	HEADER_BYTE_LENGTH : integer := 14;
	DATA_MIN_BYTE_LENGTH : integer := 46;
	FCS_BYTE_LENGTH : integer := 4;
	WAIT_BYTE_LENGTH : integer := 12; --IGB Byte length
	MII_LENGTH : integer := 4;

);
port (

	data_in_buf : in  std_logic_vector ( DATA_IN_WIDTH - 1 downto 0 );
	clk , rst : in std_logic;
	full , empty : in std_logic;
	--rd_en : out std_logic;
	txd : out  std_logic_vector ( MII_LENGTH - 1 downto 0 );
    start_in : in std_logic;
	tx_en : out  std_logic
);
end entity ethernet_fsm;

architecture rtl of ethernet_fsm is
constant BYTE_LENGTH : integer := 8;
--signal tx_buffer : std_logic_vector ( BYTE_LENGTH - 1 downto 0):= ( others => '0');--here will be loaded the data we want to output from whom we will get --the last 4 lsb for the txd
signal data_Crc : std_logic_vector ( DATA_IN_WIDTH - 1 DOWNTO 0 ); --stub data we would send to the crc generator
--=================FRAME CORE COMPONENTS
signal PREAMBLE_buff : std_logic_vector (BYTE_LENGTH - 1 downto 0) := "10101010"; --just alternating 1 and 0 is the preamble
signal SFD_buffer : std_logic_vector ( BYTE_LENGTH * SFD_BYTE_LENGTH - 1 downto 0 ) := "10101011";
signal HEADER_buffer : std_logic_vector ( HEADER_BYTE_LENGTH * BYTE_LENGTH - 1 downto 0) := ( others => '1');--this is long maybe better go using an array kind of
-- Destination MAC address - Source MAC Address - Type Field ( what protocol is using the network layer ipv4 (ox800) or ipv6(0x86dd) )
-- 6 byte                  - 6 byte  - 2 byte

signal FCS_buff : std_logic_vector ( FCS_BYTE_LENGTH * BYTE_LENGTH - 1 downto 0) := ( others => '0'); -- we will calculate this value and get it from the crc generator , i was thinking to add 8 bit data or 4 bit data ? to the crc generator no need for more , cuz we will send also the data to crc it but we get data only in 1 byte and we store them for 2 clock cycles technically so i guess
--=================================


--we assume that we will have a counter for each state , that we count how many bytes did we send and we can define to go to the next state or not , but since it needs to adapt to the longest byte length of the states we chose arbitrary as   4 * DATA_MIN_BYTE_LENGTH , since data byte state has the biggest byte length
signal counter_state_byte : unsigned (integer(ceil(log2(real (DATA_MIN_BYTE_LENGTH * 4)))) - 1 downto 0 ); 

--check this cuz it will be only 1 bit in our scenario ,it may be prone of issues,refereed to the tx_buffer slice, it count how many 4 bits did we get from the tx_buffer
constant buffer_length : integer := 1;
signal counter_local_buffer_slice_curr, counter_local_buffer_slice_next :  STD_LOGIC_vECTOR ( integer(ceil(log2(real(buffer_length* BYTE_LENGTH / MII_LENGTH )))) - 1 downto 0 ) := ( others => '0');



--referred  the buffers we have for each frame components, we got the biggest frame byte length after the data since we will get the data from the fifo
--we could also rotate shift the buffers so no need for the slice of the buffer , I guess better bcs we will rotate shift only the header buff assuming we will send data only to one destination mac with same type field

signal counter_buffer_Slice_curr, counter_buffer_Slice_next : unsigned ( integer ( ceil ( log2 ( real ( HEADER_BYTE_LENGTH * BYTE_LENGTH)))) - 1 DOWNTO 0 ):= ( others => '0'); 
signal counter_state_byte_curr, counter_state_byte_next : unsigned ( integer ( ceil ( log2 ( real ( HEADER_BYTE_LENGTH * BYTE_LENGTH)))) - 1 DOWNTO 0 ):= ( others => '0'); 

--==========FSM States , signals 
signal tx_buffer_curr , tx_buffer_next : std_logic_vector ( BYTE_LENGTH - 1 downto 0):= ( others => '0');--here will be loaded the data we want to output from whom we will get the last 4 lsb for the txd
type t_state is ( IDLE , PREAMBLE , SFD, header , DATA , FCS , WAIT_S );
signal curr_state , next_state : t_state := IDLE;


signal txd_curr , txd_next : std_logic_vector ( MII_length - 1 downto 0 ):= ( others => '0');
signal tx_en_curr , tx_en_next : std_logic := '0';

signal start : std_logic := '0'; --signal that will come from t he fifo or as an input
signal data_out_fifo : std_logic_vector ( tx_buffer_curr'high  downto 0  ) := ( others => '0');
signal data_out_crc_buf : std_logic_vector ( BYTE_LENGTH * FCS_BYTE_LENGTH - 1 downto 0 ) := ( others => '0');
signal crc_ce : std_logic := '0';
signal rd_en : std_logic := '0';
begin
start <= start_in;
CURR_STATE_L : process ( clk , rst)
begin
if rising_edge ( clk ) then
	if rst = '1' then
		curr_State <= IDLE;
		tx_buffer_curr <= ( others => '0');
		counter_local_buffer_slice_curr <= ( others => '0');
		counter_state_byte_curr <= ( others => '0');
		txd_curr <= ( others => '0');
		tx_en_curr <= '0';
	else
		curr_state <= next_State;
		tx_buffer_curr <= tx_buffer_next;
		counter_local_buffer_slice_curr <= counter_local_buffer_slice_next;
		counter_state_byte_curr <= counter_state_byte_next;
       
		txd_curr <= txd_next;
		tx_en_curr <= tx_en_next;
	end if;
end if;
end process CURR_STATE_L;	


NEXT_STATE_l : process (start , tx_buffer_next , CURR_STATE , counter_local_buffer_slice_curr , counter_state_byte_curr )
begin
next_state <= curr_state;
tx_buffer_next <= tx_buffer_curr;
txd_next <= txd_curr;
counter_local_buffer_slice_next <= counter_local_buffer_slice_curr;
tx_en_next <= '1';
case curr_state is 
	when IDLE => 
		tx_en_next <= '0';
		if start = '1' then
			next_state <= PREAMBLE;
			tx_buffer_next <=  PREAMBLE_buff;
			txd_next <= tx_buffer_next ( MII_LENGTH - 1 downto 0 ); --to see this logic,bcs e put tx_buffer_next at the sensitivity list this 
--logic would run and get the values correctly
			counter_local_buffer_slice_next <= ( others => '0');
		end if;
	when PREAMBLE => 
		--counter_local_buffer_slice_next <= NOT counter_local_buffer_slice_curr ;
		if counter_local_buffer_slice_curr = ( counter_local_buffer_slice_curr'length - 1 downto 0  => '0') then
			counter_state_byte_next <= counter_state_byte_curr + 1;
            counter_local_buffer_slice_next <= ( others => '1');
		else
        	counter_local_buffer_slice_next <= ( others => '0');
        end if;
		-- WE COULD use the logic also like I counter_local_buffer_slice_curr = 0 then increment the counter_byte
		if counter_state_byte_curr = to_unsigned ( PREAMBLE_BYTE_LENGTH -1 ,counter_state_byte_curr'length )  then
			next_state <= SFD;
			tx_buffer_next <= SFD_buffer;
			txd_next <= tx_buffer_next ( MII_LENGTH - 1 downto 0 );
			counter_local_buffer_slice_next <= ( others => '0');
			counter_state_byte_next <= ( others => '0');
			
		end if;
	when SFD => 
		if counter_local_buffer_slice_curr = ( counter_local_buffer_slice_curr'length - 1 downto 0  => '0') then
			counter_state_byte_next <= counter_state_byte_curr + 1;
            counter_local_buffer_slice_next <= ( others => '1');
		else
        	counter_local_buffer_slice_next <= ( others => '0');
        end if;

		if counter_state_byte_curr = SFD_BYTE_LENGTH -1 then
			next_state <= HEADER;
			tx_buffer_next <= HEADER_buffer( tx_buffer_next'length - 1 downto 0 );
			txd_next <= tx_buffer_next ( MII_LENGTH - 1 downto 0 );
			counter_local_buffer_slice_next <= ( others => '0');
			counter_state_byte_next <= ( others => '0');
			
		end if;
		
			
	when HEADER => 
		counter_local_buffer_slice_next <= NOT counter_local_buffer_slice_curr ;
		tx_buffer_next <= (MII_LENGTH - 1 downto 0 => '0' ) & tx_buffer_curr( tx_buffer_curr'high downto tx_Buffer_curr'high - MII_LENGTH + 1  );
		if counter_local_buffer_slice_curr = "0" then
			counter_state_byte_next <= counter_state_byte_curr + 1;
			HEADER_buffer <= HEADER_buffer( tx_buffer_next'length - 1 downto 0 ) & HEADER_buffer ( HEADER_buffer'high downto tx_buffer_next'length );
		end if;

		if counter_local_buffer_slice_curr = "1" then
			
			tx_buffer_next <= HEADER_buffer( tx_buffer_next'length - 1 downto 0 );
		end if;
		txd_next <= tx_buffer_next ( MII_LENGTH - 1 downto 0 );

		if counter_state_byte_curr = HEADER_BYTE_LENGTH - 2 AND counter_local_buffer_slice_curr = "0" then
			rd_en <= '1';
		end if;

		if counter_state_byte_curr = HEADER_BYTE_LENGTH -1 then
			next_state <= DATA;
			tx_buffer_next <= data_out_fifo;
			txd_next <= tx_buffer_next ( MII_LENGTH - 1 downto 0 );
			counter_local_buffer_slice_next <= ( others => '0');
			counter_state_byte_next <= ( others => '0');
			
		end if;
	when DATA => 
		counter_local_buffer_slice_next <= NOT counter_local_buffer_slice_curr ;
		tx_buffer_next <= (MII_LENGTH - 1 downto 0 => '0' ) & tx_buffer_curr( tx_buffer_curr'high downto tx_Buffer_curr'high - MII_LENGTH + 1  );
		if counter_local_buffer_slice_curr  = "0" then
			rd_en <= '1';
			counter_state_byte_next <= counter_state_byte_curr + 1;
		else 
			tx_buffer_next <= data_out_fifo;
			

		end if;
		txd_next <= tx_buffer_next ( MII_LENGTH - 1 downto 0 );--THIS COULD BE A LONG COMB CIRCUIT SO TO SEE
-- to see about the fcs , not that much complicated but it's just me that complicated it a little bit
		if counter_state_byte_curr = DATA_min_BYTE_LENGTH -1 then
			next_state <= FCS;--TO THINK ABOUT THIS
			tx_buffer_next <= data_out_crc_buf(tx_buffer_next'high downto 0 );--assuming the crc outputs a 32 bit value since its 4 bytes,correct kind of
			txd_next <= tx_buffer_next ( MII_LENGTH - 1 downto 0 );
			counter_local_buffer_slice_next <= ( others => '0');
			counter_state_byte_next <= ( others => '0');
			
		end if;

		when FCS => 
			counter_local_buffer_slice_next <= NOT counter_local_buffer_slice_curr;
			if counter_local_buffer_slice_curr  = "0" then
			
			counter_state_byte_next <= counter_state_byte_curr + 1;
			--data_out_crc
		else 
			tx_buffer_next <= data_out_crc_buf( 7 downto 0);
			

		end if;

			txd_next <= tx_buffer_next ( MII_LENGTH - 1 downto 0 ); -- I guess, ITS A BIT MESSY BUT IT MAY BE GOOD	
			if counter_state_byte_curr = FCS_BYTE_LENGTH - 1 then
				next_state <= wait_s;
				tx_en_next <= '0';
			end if;

		when wait_s => 
			--just count for as many bytes
		end case;
end process NEXT_STATE_l;

SEND_DATA_TO_CRC_GEN : process ( clk , rst)
begin
if rising_edge ( clk ) then
	if rst = '1' then
		crc_ce <= '0';
	else
		if counter_local_buffer_slice_next = "0" and ( curr_state /= IDLE or next_state = PREAMBLE ) and curr_state /= FCS then
			crc_ce <= '1';
			data_crc <= tx_buffer_next; --we assume we are giving input to the crc gen
		else
			crc_ce <= '0';
		end if;

		if counter_local_buffer_slice_curr = "0" and curr_state = FCS then
			data_out_crc_buf <= ( tx_buffer_next'length - 1 downto 0 => '0' ) & data_out_crc_buf ( data_out_crc_buf'high downto  tx_buffer_next'length ) ;
	end if;
end if;
END IF;
end process SEND_DATA_tO_CRC_GEN;
SIMULATE_FIFO : process ( clk )
begin
if rising_edge ( clk ) then
	if rd_en = '1' then
    	data_out_fifo <= ( others => '1');
        
    end if;
end if;
END PROCESS SIMULATE_FIFO;

SIMULATE_FCS : process  (clk)
begin
if rising_Edge ( clk ) then
	if crc_ce = '1' then
    	data_out_crc_buf <= ( others => '0');
     end if;
     
end if;
end process simulate_fcs;

end architecture rtl;
