----------------------------------------------------------------------------
--
--  SH-2 Register Array
--
--  This is an implementation of a Register Array for the SH-2 it uses the 
--  generic register array. Registers are accessed as single words, so 
--  pair wise access is ignored. The SH-2 has 16 32-bit registers. For
--  addressing modes one of the bases is always R0, as such this is, thus, always 
--  outputted. The other interface is used for the ALU and allows for output 
--  simultaneously for data access and the ALU, for future pipelining.
--
--  Entities included are:
--     RegArraySH2  - the register array
--
--  Revision History:
--     6 Apr 26  Simone Shevchuk       Initial revision.
--     8 Apr 26  Simone Shevchuk       Declare default values
--     15 Apr 26 Simone Shevchuk       Cleanup deprecated signals, add comments
--     11 May 26 Simone Shevchuk       Change pair access inputs to all open
----------------------------------------------------------------------------


--
--  RegArraySH2
--
--  This is a register array for SH2. The SH-2 has 16 32-bit registers through 
--  the generic regarray implementation. This generates appropriate signals
--  from the control signals and sets excess signals like double word ones 
--  appropriatley to be ignored. There is also two separate access ports and 
--  a write port to allow the registers to be used as addressable registers
--  simultaneous to their use in other blocks such as the ALU.
--  
--
--  Inputs:
--    reg_in        - input bus to the register writes
--    reg_in_sel    - which register to write 
--    reg_store     - actually write to a register
--    reg_a_sel     - register to read onto bus a for ALU
--    reg_b_sel     - register to read onto bus b for ALU
--    reg_ax_in     - input bus for address register updates
--    reg_ax_in_sel - which address register to write 
--    reg_ax_store  - actually write to an address register
--    reg_a2_sel    - register to read onto address bus 2 
--    clock         - the system clock
--
--  Outputs:
--    reg_a       - register value for bus a
--    reg_b       - register value for bus b
--    reg_a1      - register value for address bus 1, R0
--    reg_a2      - register value for address bus 2
--

library ieee;
use ieee.std_logic_1164.all;

entity  RegArrSH2  is

    port(
        reg_in          : in   std_logic_vector(31 downto 0);
        reg_in_sel      : in   integer  range 15 downto 0;
        reg_store       : in   std_logic;
        reg_a_sel       : in   integer  range 15 downto 0;
        reg_b_sel       : in   integer  range 15 downto 0;
        reg_ax_in       : in   std_logic_vector(31 downto 0);
        reg_ax_sel      : in   integer  range 15 downto 0;
        reg_ax_store    : in   std_logic;
        reg_a2_sel      : in   integer  range 15 downto 0;
        clock           : in   std_logic;
        reg_a           : out  std_logic_vector(31 downto 0);
        reg_b           : out  std_logic_vector(31 downto 0);
        reg_a1          : out  std_logic_vector(31 downto 0);
        reg_a2          : out  std_logic_vector(31 downto 0)
    );

end  RegArrSH2;

architecture behavioral of RegArrSH2 is

    signal reg_a1_sel   : integer := 0; -- set to 0 to always read R0 for address bus 1

    begin 
        -- instantiate generic register array with appropriate signal mapping 
        Regs : entity work.RegArray
        generic map (
            regcnt   => 16,   -- 16 registers
            wordsize => 32    -- 32-bit wide
        )
        port map (
            RegIn      => reg_in,
            RegInSel   => reg_in_sel,
            RegStore   => reg_store,
            RegASel    => reg_a_sel,
            RegBSel    => reg_b_sel,
            RegAxIn    => reg_ax_in,
            RegAxInSel => reg_ax_sel,
            RegAxStore => reg_ax_store,
            RegA1Sel   => reg_a1_sel,
            RegA2Sel   => reg_a2_sel,
            RegDIn     => (others => '0'),
            RegDInSel  => 0,
            RegDStore  => '0',
            RegDSel    => 0,
            clock      => clock,
            RegA       => reg_a,
            RegB       => reg_b,
            RegA1      => reg_a1,
            RegA2      => reg_a2,
            RegD       => open 
        );

end behavioral;
