----------------------------------------------------------------------------
--
--  SH-2 Program Memory Access Unit 
--
--  This is an implementation of a Program Memory Access Unit for the SH-2 it 
--  uses the generic memory unit. The generic address unit takes in a number of
--  sources and offsets and allows for pre and post increment and decrement. 
--  The PAU uses this to generate the appropriate address for instruction 
--  fetches and updates the PC. 
--
--  Entities included are:
--     PAUSH2  - the program access unit for SH2
--
--  Revision History:
--     9 Apr 26  Simone Shevchuk       Initial revision.
--     11 Apr 26 Simone Shevchuk       Update PC and PR added
--     13 Apr 26 Simone Shevchuk       VBR moved to DAU, shifter entity removed, explicit mapping for arrays
----------------------------------------------------------------------------

--
--  PAUSH2
--
--
--  This is a program memory access unit for the SH-2. It uses the generic 
--  memory access unit to generate the appropriate address for instruction 
--  fetches. It outputs along the address bus the address for the next instruction, 
--  this can also be fed directly into the PR to store the return address. 
--  Pre/post is set to pre by MAU standards meaning use the original address and 
--  no inc/dec since the inc/dec is never used since offset applies changes.
--  The PAU has an input for the offset to be added to the PC for jump.
--  A shifter is used to shift the offset left by 1 bit to multiply by 2 which 
--  some instructions require. All offsets are sign extended in the control unit 
--  before coming in. The possible offsets are the sign extended shifted value 
--  from instructions (0) (note shifting is done in the PAU but sign extension
--  done in the control unit); value from a register (1), zero (2), and one (3) 
--  which is actually equivalent to 4 bytes for an increment. The value for an 
--  Address source can be current PC (0), PR(1), datadatabus(2) or 0(3) for 
--  relative/normal increments, returns, handling interrupts and absolute jumps, 
--  respectively. The PC holds the value of the current instruction being decoded
--  and is updated to the next instruction address on every clock cycle. 
--   
--
--  Inputs:
--    src_sel       - source to use (log srccnt bits)
--    datadata_src  - value from VBR and offset for reset vector for interrupt handling
--    addr_off      - offset given from instruction
--    addr_reg      - offset given from register 
--    offset_sel    - offset to use (log offsetcnt bits)
--    pr_sel        - signal to write to PR with current PC or register
--    clock         - the system clock
--    reset         - the system reset signal
--
--  Outputs:
--    address_out   - address bus (32 bits), next instruction address to fetch
--

library ieee;
use ieee.std_logic_1164.all;
use work.array_type_pkg.all;

entity  PAUSH2  is

    port(
        src_sel         : in   integer range 3 downto 0;
        datadata_src    : in   std_logic_vector(31 downto 0); 
        addr_off        : in   std_logic_vector(31 downto 0);
        addr_reg        : in   std_logic_vector(31 downto 0);
        offset_sel      : in   integer  range 3 downto 0;
        pr_sel          : in   integer range 2 downto 0; 
        clock           : in   std_logic;
        reset           : in   std_logic;
        address_out     : buffer  std_logic_vector(31 downto 0)
    );

end  PAUSH2;

architecture behavioral of PAUSH2 is

    constant ZERO   : std_logic_vector(31 downto 0) := (others => '0'); -- constant for 0 value
    constant ONE    : std_logic_vector(31 downto 0) :=  x"00000004";    
    -- constant for 1 value, which is 4 bytes since instructions are word aligned and incrementing 
    -- by 1 means incrementing by 4 bytes to get to the next instruction
    signal PC       : std_logic_vector(31 downto 0) := ZERO;
    signal PR       : std_logic_vector(31 downto 0) := ZERO;
    signal next_PC  : std_logic_vector(31 downto 0) := ZERO;
    signal Shift2Res: std_logic_vector(31 downto 0);                    
    -- result of shifting offset left by 1 bit to multiply by 2 for jump instructions with shifted offsets
    signal src_array: std_logic_array(3 downto 0)(31 downto 0) ;        -- array of sources for MAU

    begin 

        Regs : entity work.MemUnit
        generic map (
            srcCnt   => 4,   -- 4 sources, PC, PR, VBR and 0
            offsetCnt => 4,  -- 4 offsets, from instruction, register/datadatabus, 0 and 1 (4 bytes for increment)
            wordsize => 32   -- 32-bit wide
        )
        port map (
            AddrSrc     => src_array,
            SrcSel      => src_sel,
            AddrOff     => (0 => Shift2Res, 1 => addr_reg, 2 => ZERO, 3 => ONE), 
            OffsetSel   => offset_sel,
            IncDecSel   => '0', -- not used since no inc/dec
            IncDecBit   => 0,   -- not used since no inc/dec
            PrePostSel  => '0', -- always use pre since MAU then uses source address
            Address     => address_out,
            AddrSrcOut  => open
        );

        -- shift left by 1 bit to multiply by 2, used for jump instructions with shifted offsets
        Shift2Res <= addr_off(30 downto 0) & '0'; 
        
        -- update next PC to output of MAU which is the address of the next instruction to fetch
        next_PC <= address_out; 

        -- array of address sources to be input into generic memory unit
        src_array <= (0 => PC, 1 => PR, 2 => datadata_src, 3 => ZERO); 

        process(clock)
        begin
        if rising_edge(clock) then
            if reset = '1' then
                PC <= ZERO; -- reset PC to 0 on reset
                PR <= ZERO; -- reset PR to 0 on reset
            else
                if pr_sel = 1 then 
                    PR <= PC; -- write current PC to PR for jump instructions
                elsif pr_sel = 2 then
                    PR <= addr_reg; -- write register value to PR for jump instructions
                end if;

                PC <= next_PC; -- update PC to next instruction address
            end if;        
        end if;
        end process;


end behavioral;