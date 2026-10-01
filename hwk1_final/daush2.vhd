----------------------------------------------------------------------------
--
--  SH-2 Data Memory Access Unit 
--
--  This is an implementation of a Data Memory Access Unit for the SH-2 it 
--  uses the generic memory unit. The generic address unit takes in a number of
--  sources and offsets and allows for pre and post increment and decrement. 
--  The DAU uses this to generate the appropriate address for data accesses.
--
--  Entities included are:
--     ShiftL  - shifter for shifting offset from instruction for multiplication
--     DAUSH2  - the data access unit for SH2
--
--  Revision History:
--     12 Apr 26  Simone Shevchuk       Initial revision.
--     13 Apr 26  Simone Shevchuk       Set maxincdec bit for generic memory unit
--     14 Apr 26  Simone Shevchuk       Added VBR and GBR, and reset. PC masking
--     15 Apr 26  Simone Shevchuk       Comments added
----------------------------------------------------------------------------

--
--  ShiftL
--
--  This is the shifter for doing left shift by 0, 1, or 2 places in the DAU. 
--
--  Generics:
--    wordsize - width of the shifter in bits (default 32)
--               must be an even number of bits
--
--  Inputs:
--    SOp     - operand
--    ShiftSel - shift to apply to offset, 0 for no shift, 1 for shift by 1 (multiply by 2), 2 for shift by 2 (multiply by 4)
--
--  Outputs:
--    SResult - shift result
--

library ieee;
use ieee.std_logic_1164.all;

entity  ShiftL  is

    generic (
        wordsize : integer := 32      -- default width is 8-bits
    );

    port(
        SOp         : in    std_logic_vector(wordsize - 1 downto 0);    -- operand
        ShiftSel    : in    integer range 2 downto 0;                   -- shift to apply to offset
        SResult     : out   std_logic_vector(wordsize - 1 downto 0)     -- shift result
    );

end  ShiftL;


architecture  dataflow  of  ShiftL  is
begin

    -- concatenate the appropriate number of 0s to the right of the operand based on shift sel
    SResult  <= SOp(wordsize - 2 downto 0) & '0'    when ShiftSel = 1 else
                SOp(wordsize - 3 downto 0) & "00"   when ShiftSel = 2 else
                SOp(wordsize - 1 downto 0); -- if no shift just pass through

end  dataflow;


--
--  DAUSH2
--
--
--  This is a data memory access unit for the SH-2. It uses the generic 
--  memory access unit to generate the appropriate address for data 
--  accesses. It outputs along the address bus the address for the next data 
--  access and updates the base address when an increment or decrement is done 
--  along the addrsrcout bus. Inputs for the address source can be some register,
--  VBR, GBR, or, PC. The offset can be be from the instruction or from R0. 
--  The offset (from instruction) is already assumed to be sign-extended. A shifter 
--  is also used before the offset is passed in to the generic memory unit to
--  to multiply the offset by 1, 2, or 4 depending on the instruction. Only 
--  post increment and pre decrement are used in the SH-2, and these are set
--  accoridngly as it can be done by 1 2 or 4 by selecting the incdecbit. The VBR
--  and GBR are kept inside the DAU. The VBR is reset to 0 on reset and can be 
--  loaded with the current PC for interrupt handling. The PC input is masked
--  to 0 on the lower 2 bits when used as an address source
--
--
--  Inputs:
--    addr_PC    - PC value to use as address source for PC-relative accesses
--    addr_Reg   - value from register to use as address source for register indirect accesses
--    src_sel    - source to use (log srccnt bits)
--    shift_sel  - shift (multiplication) to apply to offset, 0 for no shift, 1 for shift by 1 (multiply by 2), 2 for shift by 2 (multiply by 4)
--    offset_ins - offset value given from instruction
--    offset_reg - offset value from register for register indirect with offset accesses
--    offset_sel - offset to use (log offsetcnt bits) (1 for register offset, 0 for instruction offset)
--    inc_dec_sel- whether to increment (0) or decrement (1) address source
--    inc_dec_bit- bit of address source to increment/decrement
--    pre_post_sel- whether to pre- (0) or post- (1) inc/dec address source, note that
--                  the generic memory unit so that pre and post are implemented, so that
--                  pre means use the original source and post means use the incremented/decremented source.
--    clock       - the system clock
--    reset       - system reset, used to reset VBR to 0
--    gbr_write  - signal to load GBR with value from register for interrupt handling
--    vbr_write  - signal to load VBR with value from register for interrupt handling
--
--  Outputs:
--    address_out    - address bus (wordsize bits)
--    addr_src_out - incremented/decremented source, goes to register file to update base address (wordsize bits)
--

library ieee;
use ieee.std_logic_1164.all;
use work.array_type_pkg.all;

entity  DAUSH2  is
    port(
        addr_PC         : in   std_logic_vector(31 downto 0);
        addr_reg        : in   std_logic_vector(31 downto 0);
        src_sel         : in   integer range 3 downto 0;
        shift_sel       : in   integer range 2 downto 0;
        offset_ins      : in   std_logic_vector(31 downto 0);
        offset_reg      : in   std_logic_vector(31 downto 0);
        offset_sel      : in   integer  range 1 downto 0;
        inc_dec_sel     : in   std_logic;
        inc_dec_bit     : in   integer  range 31 downto 0;
        pre_post_sel    : in   std_logic;
        clock           : in   std_logic;
        reset           : in   std_logic;
        gbr_write       : in   std_logic;
        vbr_write       : in   std_logic;
        address_out     : out  std_logic_vector(31 downto 0);
        addr_src_out    : out  std_logic_vector(31 downto 0)
    );

end  DAUSH2;

architecture behavioral of DAUSH2 is

    signal temp_PC  : std_logic_vector(31 downto 0);            
    -- temp PC with lower 2 bits masked to 0 for word-aligned accesses when using PC as source nd shifting by 2 for word offset
    signal GBR      : std_logic_vector(31 downto 0);            -- global base register for GBR-relative accesses
    signal VBR      : std_logic_vector(31 downto 0);            -- vector base register for VBR-relative accesses, used to hold vector for interrupt handling
    signal ShiftRes : std_logic_vector(31 downto 0);            -- result from shifter to be used as offset input to generic memory unit
    signal src_array: std_logic_array(3 downto 0)(31 downto 0); -- array of address sources to be input into generic memory unit, includes register, GBR, VBR, and PC

    begin 

        Regs : entity work.MemUnit
        generic map (
            srcCnt       => 4,   -- 4 sources, register, VBR, GBR, PC
            offsetCnt    => 2,   -- 2 offsets, from instruction and register
            maxIncDecBit => 31,  -- allow inc/dec at any bit position (byte/word/longword)
            wordsize     => 32   -- 32-bit wide
        )
        port map (
            AddrSrc     => src_array,
            SrcSel      => src_sel,
            AddrOff     => (offset_reg, ShiftRes), -- 1 for register offset, 0 for instruction offset
            OffsetSel   => offset_sel,
            IncDecSel   => inc_dec_sel, 
            IncDecBit   => inc_dec_bit, 
            PrePostSel  => pre_post_sel, 
            Address     => address_out,
            AddrSrcOut  => addr_src_out
        );

        -- instantiate the shifter to shift the instruction offset
        ShiftUnit: entity work.ShiftL
        generic map (
            wordsize => 32    -- 32-bit wide
        )
        port map (
            SOp         => offset_ins,
            ShiftSel    => shift_sel,
            SResult     => ShiftRes
        );

        temp_PC <= addr_PC(31 downto 2) & "00" when src_sel = 3 and shift_sel = 2 else
                  addr_PC; -- if not using PC or register as source, just pass

        -- array of address sources to be input into generic memory unit
        src_array <= (0 => addr_reg, 1 => GBR, 2 => VBR, 3 => temp_PC);

        process(clock)
        begin
        if rising_edge(clock) then
            if reset = '1' then
                VBR <= (others => '0'); -- reset VBR to 0 on reset
            else
                if vbr_write = '1' then
                    VBR <= addr_reg; -- write current PC to VBR for interrupt handling
                end if;
                if gbr_write = '1' then
                    GBR <= addr_reg; -- write current PC to GBR for interrupt handling
                end if;
            end if;        
        end if;
        end process;


end behavioral;