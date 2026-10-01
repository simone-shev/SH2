----------------------------------------------------------------------------
--
--  SH-2 Program Memory Access Unit
--
--  This is an implementation of a Program Memory Access Unit for the SH-2 it
--  uses the generic memory unit. The generic address unit takes in a number of
--  sources and offsets and allows for pre and post increment and decrement.
--  The PAU uses this to generate the appropriate address for instruction
--  fetches and updates the PC. In the pipelined version, the live PC naturally
--  equals instruction_addr + 4 when the instruction is in the EX stage (two
--  fetches have occurred since), so no explicit PC+4 adder is needed.
--
--  Entities included are:
--     PAUSH2  - the program access unit for SH2
--
--  Revision History:
--     9 Apr 26  Simone Shevchuk       Initial revision.
--     11 Apr 26 Simone Shevchuk       Update PC and PR added
--     13 Apr 26 Simone Shevchuk       VBR moved to DAU, shifter entity removed, explicit mapping for arrays
--     30 Apr 26 Simone Shevchuk       Add PR as an output which will go to reg array for STS
--     1 May 26  Simone Shevchuk       Change PC to in increment by 2
--     8 May 26  Simone Shevchuk       PC+4 branch base and delay slot support
--     17 May 26 Simone Shevchuk       Remove delay_slot/delay_active/branch_target
--                                     FSM, remove PC+4 adder, add stall/branch_taken 
--                                     control inputs
--
----------------------------------------------------------------------------

--
--  PAUSH2
--
--  This is a program memory access unit for the SH-2. It uses the generic 
--  memory access unit to generate the appropriate address for instruction 
--  fetches. It outputs along the address bus the address for the next instruction
--  , the current PC, unless stalled or redirected by a taken branch. 
--  Pre/post is set to pre by MAU standards meaning use the original address and 
--  no inc/dec since the inc/dec is never used since offset applies changes.
--  The PAU has an input for the offset to be added to the PC for jump.
--  A shifter is used to shift the offset left by 1 bit to multiply by 2 which 
--  some instructions require. All offsets are sign extended in the control unit 
--  before coming in. The possible offsets are the sign extended shifted value 
--  from instructions (0) (note shifting is done in the PAU but sign extension
--  done in the control unit); value from a register (1), zero (2), and one (3) 
--  which is actually equivalent to 2 bytes for an increment. The value for an
--  Address source can be current PC (0), PR (1), addr_reg (2), or PC (3) for
--  relative branches, returns, register jumps (JMP/JSR @Rm, BRAF/BSRF), and
--  an alias of 0 (unused) respectively. An internal mux selects MemUnit inputs based on
--  branch_taken:
--    branch_taken='0': src=PC(0), offset=ONE(3) -> mau_addr = PC+2
--    branch_taken='1': src/offset from EX pipeline register -> branch target
--  PC always loads from mau_addr when not stalled. 
--  PR is written from the WB stage via pr_sel/pr_src, for instructions like
--  BSR/JSR (save return address), LDS Rm,PR, and LDS.L @Rm+,PR.
--    pr_sel = 0: no write
--    pr_sel /= 0: PR <= pr_src (WB stage muxes the correct value)
--
--  Inputs:
--    src_sel       - MemUnit source to use (from EX pipeline register) (log srccnt bits)
--    addr_off      - offset given from instruction (sign-extended, from EX)
--    addr_reg      - register value offset or source (from EX)
--    offset_sel    - MemUnit offset to use (from EX pipeline register)
--    pr_src  - value to write to PR (muxed in WB stage) (log offsetcnt bits)
--    pr_sel        - signal to write to PR or not (from WB stage)
--    branch_taken  - when '1' and not stalled, MemUnit computes branch target
--    stall         - when '1', hold PC (structural hazard or load-use stall)
--    clock         - the system clock
--    reset         - the system reset signal
--
--  Outputs:
--    address_out   - address bus (32 bits), next instruction address to fetch (used in IF)
--    PC_out        - live PC exposed for DAU PC-relative addressing and
--                    return address use in EX
--    PR            - PR value to be written to register file and RTS instructions
--

library ieee;
use ieee.std_logic_1164.all;
use work.array_type_pkg.all;

entity  PAUSH2  is

    port(
        src_sel         : in   integer range 3 downto 0;
        addr_off        : in   std_logic_vector(31 downto 0);
        addr_reg        : in   std_logic_vector(31 downto 0);
        offset_sel      : in   integer range 3 downto 0;
        branch_taken    : in   std_logic;
        stall           : in   std_logic;
        pr_sel          : in   integer range 3 downto 0;
        pr_src    : in   std_logic_vector(31 downto 0);
        clock           : in   std_logic;
        reset           : in   std_logic;
        address_out     : out  std_logic_vector(31 downto 0);
        PC_out          : out  std_logic_vector(31 downto 0); -- PC exposed for DAU PC-relative addressing
        PR              : out  std_logic_vector(31 downto 0) -- output PR for STS
    );

end  PAUSH2;

architecture behavioral of PAUSH2 is

    constant ZERO : std_logic_vector(31 downto 0) := (others => '0'); -- constant for 0 value
    constant ONE  : std_logic_vector(31 downto 0) := x"00000002";
    -- constant for 1 value, which is 2 bytes since instructions are word aligned and incrementing 
    -- by 1 means incrementing by 2 bytes to get to the next instruction
    signal PC          : std_logic_vector(31 downto 0) := ZERO;
    signal PR_internal : std_logic_vector(31 downto 0) := ZERO;
    signal Shift2Res   : std_logic_vector(31 downto 0);
    signal mau_addr    : std_logic_vector(31 downto 0);
    signal src_array   : std_logic_array(3 downto 0)(31 downto 0);

    -- internal muxed selects, sequential (PC+2) or branch target, uses branch_taken
    signal int_src_sel    : integer range 3 downto 0;
    signal int_offset_sel : integer range 3 downto 0;

begin

    -- mux MemUnit inputs branch target from EX or sequential PC+2
    int_src_sel    <= src_sel    when branch_taken = '1' else 0;
    int_offset_sel <= offset_sel when branch_taken = '1' else 3;

    Regs : entity work.MemUnit
    generic map (
        srcCnt       => 3,
        offsetCnt    => 4,
        wordsize     => 32
    )
    port map (
        AddrSrc    => src_array,
        SrcSel     => int_src_sel,
        AddrOff    => (0 => Shift2Res, 1 => addr_reg, 2 => ZERO, 3 => ONE),
        OffsetSel  => int_offset_sel,
        IncDecSel  => '0',
        IncDecBit  => 0,
        PrePostSel => '0',
        Address    => mau_addr,
        AddrSrcOut => open
    );

    Shift2Res <= addr_off(30 downto 0) & '0';

    src_array <= (0 => PC, 1 => PR_internal, 2 => addr_reg);

    -- IF stage always fetches from current PC
    address_out <= PC;
    PC_out      <= PC;
    PR          <= PR_internal;

    process(clock)
    begin
        if rising_edge(clock) then
            if reset = '0' then
                PC          <= ZERO;
                PR_internal <= ZERO;
            else
                if pr_sel /= 0 then
                    PR_internal <= pr_src;
                end if;
                if stall = '0' then
                    PC <= mau_addr;
                end if;
            end if;
        end if;
    end process;

end behavioral;
