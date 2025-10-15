library IEEE;

use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;


entity sync_fifo is
generic (
	DATA_IN_WIDTH : integer := 8;
	FIFO_DEPTH : integer := 128;
	
);
port (
	clk , rst : in std_logic;
	m_axis_data : in std_logic_vector ( DATA_IN_WIDTH - 1 downto 0 );
	m_axis_valid : in std_logic;
	s_axis_ready : out std_logic;
	data_out : out  std_logic_vector ( DATA_IN_WIDTH - 1 downto 0);
	full , empty : out std_logic;
    fifo_count : out std_logic_vector ( integer (ceil ( log2 ( real ( FIFO_DEPTH)))) - 1 + 1 downto 0 ); -- we add additional bit cuz 0 in fifo count means no data
	wr_en , rd_en : in std_logic
	

);
end entity sync_fifo;

architecture rtl of sync_fifo is

signal wr_count , rd_count : unsigned ( integer (ceil ( log2 ( real ( FIFO_DEPTH)))) - 1  + 1 downto 0 ) := ( others => '0'); -- we add an extra bit to detect the wrap
signal full_sig , empty_sig : std_logic := '0';

type t_fifo is array ( 0 to FIFO_DEPTH - 1) of std_logic_vector ( DATA_IN_WIDTH - 1 downto 0 );
signal fifo_buf : t_fifo := ( others => ( others => '0'));
signal wr_allow , rd_allow : std_logic := '0';
signal fifo_count_Reg : unsigned ( integer (ceil ( log2 ( real ( FIFO_DEPTH)))) - 1 + 1  downto 0 ) := ( others => '0');
signal s_axis_ready_sig : std_logic := '0';
begin

full_sig <= '1' when (  wr_count ( wr_count ' high) /= rd_count (rd_count 'high)  and wr_count ( wr_count'high - 1 downto wr_count'low) = rd_count ( rd_count'high - 1 downto rd_count'low)) else
	    '0';

empty_sig <= '1' when wr_count = rd_count else
	     '0';

full <= full_sig; -- I guess not necessary
empty <= empty_sig;

fifo_Count <= std_logic_Vector ( fifo_count_reg );
s_axis_ready_sig <= not full_sig;
s_axis_ready <= s_axis_Ready_sig;

wr_allow <= '1' when  wr_en = '1' and m_axis_valid = '1' and s_axis_ready_sig = '1' and full_sig = '0' else
 '0';
rd_allow <= '1' when rd_en = '1' and empty_sig = '0' else
			'0';
fifo_count_Resolve : process ( clk )
begin
	if rising_edge ( clk ) then
    		if rst = '1' then
            		fifo_count_reg <= ( others => '0');
             else 
             	if (  wr_allow = '1') and (   rd_allow = '0') then
                		 fifo_Count_Reg <= fifo_count_Reg + 1;
               elsif ( wr_allow = '0') and rd_allow = '1' then
               		fifo_count_reg <= fifo_Count_REg - 1;
               end if;
               end if;
    end if;


end process;
write_logic : process ( clk )
begin
	if rising_edge ( clk ) then
		if rst = '1' then
			wr_count <= ( others => '0');
			--full_reg <= '0';
		else
			if wr_en = '1' and m_axis_valid = '1' and s_axis_ready_sig = '1' and full_sig = '0' then -- technically also the wr_en = axis_valid , also the ready sig = not full_sig in our use case but we will take into account also to not overflow so the logic will change
				wr_count <= wr_count + 1;
				fifo_buf ( to_integer (wr_count( wr_count'high - 1 downto wr_count'low ))) <= m_axis_data;
			end if;
				
				

		end if;

	end if;
end process write_logic;

read_logic : process ( clk )
begin
	if rising_edge ( clk ) then
		if rst = '1' then
			rd_count <= ( others => '0');
		else
			if rd_en = '1' and empty_sig = '0' then
				rd_Count <= rd_count + 1; -- precalculate the next address
				data_out <= fifo_buf ( to_integer ( rd_count( rd_count'high - 1 downto  rd_count'low)));
			end if;
		end if;
	end if;

end process read_logic;

end architecture rtl;
