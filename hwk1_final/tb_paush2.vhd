-- =============================================================================
-- tb_PAUSH2.vhd
-- Exhaustive Test Bench for the SH-2 Program Address Unit (PAUSH2)
--
-- DUT Interface Assumptions (from entity + clarifications):
--   src_sel    : integer range 3 downto 0
--                  0 = PC (current PC is base address)
--                  1 = PR (procedure register is base address)
--                  2 = datadata_src (databus -- absolute/interrupt jump target)
--                  3 = 0  (zero base -- used with absolute offset from register)
--
--   offset_sel : integer range 3 downto 0
--                  0 = sign-extended displacement shifted left 1 in PAU
--                      (addr_off already sign-extended by CU; PAU left-shifts by 1)
--                  1 = addr_reg  (full 32-bit register value, no shift)
--                  2 = 0x00000000 (zero offset -- PC hold / no movement)
--                  3 = 0x00000004 (constant +4 -- sequential instruction fetch)
--
--   pr_sel     : integer range 2 downto 0
--                  0 = hold PR unchanged
--                  1 = write current PC into PR  (BSR/BSRF/JSR link)
--                  2 = write addr_reg into PR    (load-to-PR variant)
--
--   PC register inside DUT is updated on rising clock edge.
--   reset is synchronous active-high; PC <- 0, PR <- 0.
--
-- Test Groups
--   T01  Reset behaviour
--   T02  Sequential fetch  (src=PC, off=+4)
--   T03  PC-hold / NOP     (src=PC, off=0)
--   T04  BF/BT 8-bit displacement, positive
--   T05  BF/BT 8-bit displacement, negative
--   T06  BRA/BSR 12-bit displacement, positive
--   T07  BRA/BSR 12-bit displacement, negative
--   T08  Maximum positive 12-bit displacement
--   T09  Maximum negative 12-bit displacement
--   T10  BRAF/BSRF  -- register offset added to PC
--   T11  JMP/JSR    -- absolute address from register  (src=0, off=reg)
--   T12  RTS        -- return via PR  (src=PR, off=+4)
--   T13  RTE        -- return via databus  (src=databus, off=+4)
--   T14  Interrupt / TRAPA vector fetch (src=databus, off=0)
--   T15  pr_sel=1   -- PC saved into PR during BSR/JSR
--   T16  pr_sel=2   -- register value written into PR
--   T17  pr_sel=0   -- PR unchanged across branch
--   T18  Zero offset with non-zero base (src=PR, off=0)
--   T19  Sign-extension correctness: large positive displacement
--   T20  Sign-extension correctness: max negative displacement
--   T21  addr_reg large positive value (BRAF far forward)
--   T22  addr_reg large negative value (BRAF far backward)
--   T23  datadata_src passthrough with zero offset
--   T24  datadata_src passthrough with +4 offset (RTE pattern)
--   T25  Sequential multi-cycle execution run
--   T26  Reset mid-execution
--   T27  All-ones displacement (offset_sel=0, addr_off=0xFFFFFFFF)
--   T28  All-ones addr_reg   (offset_sel=1)
--   T29  Wrap-around: PC near 0xFFFFFFFF + increment
--   T30  Branch to address 0 (reset vector)
--
--
--  Revision History:
--    13 Apr 26  Claude Code    Initial revision.
--    14 Apr 26  Simone Shevchuk  Restart the whole thing ^_^, reset clock timing
--    15 Apr 26  Claude Code    Added test cases for edge cases.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_PAUSH2 is
end entity tb_PAUSH2;

architecture behav of tb_PAUSH2 is

    -- -------------------------------------------------------------------------
    -- Component declaration
    -- -------------------------------------------------------------------------
    component PAUSH2 is
        port(
            src_sel         : in  integer range 3 downto 0;
            datadata_src    : in  std_logic_vector(31 downto 0);
            addr_off        : in  std_logic_vector(31 downto 0);
            addr_reg        : in  std_logic_vector(31 downto 0);
            offset_sel      : in  integer range 3 downto 0;
            pr_sel          : in  integer range 2 downto 0;
            clock           : in  std_logic;
            reset           : in  std_logic;
            address_out     : buffer std_logic_vector(31 downto 0)
        );
    end component PAUSH2;

    -- -------------------------------------------------------------------------
    -- Stimulus signals
    -- -------------------------------------------------------------------------
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal src_sel      : integer range 3 downto 0 := 0;
    signal datadata_src : std_logic_vector(31 downto 0) := (others => '0');
    signal addr_off     : std_logic_vector(31 downto 0) := (others => '0');
    signal addr_reg     : std_logic_vector(31 downto 0) := (others => '0');
    signal offset_sel   : integer range 3 downto 0 := 3;
    signal pr_sel       : integer range 2 downto 0 := 0;
    signal address_out  : std_logic_vector(31 downto 0);

    -- -------------------------------------------------------------------------
    -- Clock generation: 20 ns period (50 MHz)
    -- -------------------------------------------------------------------------
    constant CLK_PERIOD : time := 20 ns;

    -- -------------------------------------------------------------------------
    -- Test infrastructure
    -- -------------------------------------------------------------------------
    signal test_num     : integer := 0;
    signal pass_count   : integer := 0;
    signal fail_count   : integer := 0;

    -- -------------------------------------------------------------------------
    -- Helper: one clock cycle delay
    -- -------------------------------------------------------------------------
    procedure clk_cycle(signal clk_sig : in std_logic) is
    begin
        wait until rising_edge(clk_sig);
        wait for CLK_PERIOD / 4;   -- settle after edge
    end procedure;

    -- -------------------------------------------------------------------------
    -- Helper: check address_out against expected value
    -- -------------------------------------------------------------------------
    -- Simple hex image: converts SLV to hex string (no to_hstring in VHDL-93)
    function slv_to_hex(slv : std_logic_vector(31 downto 0)) return string is
        constant hex_chars : string(1 to 16) := "0123456789ABCDEF";
        variable result    : string(1 to 8);
        variable nibble    : integer;
    begin
        for i in 0 to 7 loop
            nibble := to_integer(unsigned(slv(31 - i*4 downto 28 - i*4)));
            result(i+1) := hex_chars(nibble+1);
        end loop;
        return result;
    end function;

    procedure check(
        signal   addr       : in  std_logic_vector(31 downto 0);
        constant expected   : in  std_logic_vector(31 downto 0);
        constant test_id    : in  string;
        variable pcount     : inout integer;
        variable fcount     : inout integer
    ) is
    begin
        if addr = expected then
            report "[PASS] " & test_id &
                   "  got=0x" & slv_to_hex(addr) severity note;
            pcount := pcount + 1;
        else
            report "[FAIL] " & test_id &
                   "  expected=0x" & slv_to_hex(expected) &
                   "  got=0x"      & slv_to_hex(addr) severity error;
            fcount := fcount + 1;
        end if;
    end procedure;

    -- -------------------------------------------------------------------------
    -- Convenience: sign-extend 8-bit displacement and shift left 1
    --   Models what the PAU shifter does for BF/BT (offset_sel=0)
    --   The CU supplies the sign-extended value; PAU shifts left by 1.
    -- -------------------------------------------------------------------------
    function sext8_shl1(d : std_logic_vector(7 downto 0))
        return std_logic_vector is
        variable sx : signed(31 downto 0);
    begin
        sx := resize(signed(d), 32);
        return std_logic_vector(shift_left(sx, 1));
    end function;

    -- Sign-extend 12-bit displacement and shift left 1
    --   Models BRA/BSR (offset_sel=0, 12-bit sign-extended by CU)
    function sext12_shl1(d : std_logic_vector(11 downto 0))
        return std_logic_vector is
        variable sx : signed(31 downto 0);
    begin
        sx := resize(signed(d), 32);
        return std_logic_vector(shift_left(sx, 1));
    end function;

    -- Add two 32-bit unsigned vectors with wrap-around
    function add32(a, b : std_logic_vector(31 downto 0))
        return std_logic_vector is
    begin
        return std_logic_vector(unsigned(a) + unsigned(b));
    end function;

begin

    -- -------------------------------------------------------------------------
    -- DUT instantiation
    -- -------------------------------------------------------------------------
    DUT : PAUSH2
        port map(
            src_sel      => src_sel,
            datadata_src => datadata_src,
            addr_off     => addr_off,
            addr_reg     => addr_reg,
            offset_sel   => offset_sel,
            pr_sel       => pr_sel,
            clock        => clk,
            reset        => rst,
            address_out  => address_out
        );

    -- -------------------------------------------------------------------------
    -- Free-running clock
    -- -------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    -- =========================================================================
    -- Stimulus process
    -- =========================================================================
    stimulus : process
        variable pcount : integer := 0;
        variable fcount : integer := 0;

        -- Captures the current address_out value just after clock edge
        variable prev_addr : std_logic_vector(31 downto 0);

    begin

        -- =====================================================================
        -- T01: Reset behaviour
        --      address_out is COMBINATORIAL: output = src + offset immediately.
        --      PC register is 0 during reset; with offset_sel=3 (+4) the
        --      combinatorial output is 0+4=4 even while reset is held.
        --      After reset releases, behaviour is identical (PC still 0 until
        --      the next rising edge latches a new value).
        -- =====================================================================
        test_num  <= 1;
        rst       <= '1';
        src_sel   <= 0;          -- PC
        offset_sel<= 3;          -- +4
        pr_sel    <= 0;
        addr_off  <= (others => '0');
        addr_reg  <= (others => '0');
        datadata_src <= (others => '0');
        clk_cycle(clk);
        -- PC=0 (reset), offset=+4 -> address_out = 0+4 = 4 combinatorially
        check(address_out, x"00000004",
              "T01a: reset held, off=+4 -> address_out=0x4 (PC=0 comb)",
              pcount, fcount);

        -- Reset still held, switch to zero offset -> address_out = 0+0 = 0
        offset_sel <= 2;         -- 0 offset
        clk_cycle(clk);
        check(address_out, x"00000000",
              "T01b: reset held, off=0 -> address_out=0x0",
              pcount, fcount);
        rst <= '0';

        -- =====================================================================
        -- T02: Sequential fetch  (src=PC, offset_sel=3 -> +4)
        --      After reset PC=0; address_out immediately shows 0+4=4.
        --      Each rising edge latches address_out into PC, so:
        --        before cycle 1: PC=0, output=4
        --        after  cycle 1: PC=4, output=8
        --        after  cycle 2: PC=8, output=12 (0xC)
        --        after  cycle 3: PC=12, output=16 (0x10)
        -- =====================================================================
        test_num   <= 2;
        src_sel    <= 0;         -- PC
        offset_sel <= 3;         -- +4
        pr_sel     <= 0;
        -- rst just released; PC=0; address_out is already combinatorially 0+4=4
        -- One more clk_cycle latches PC=4, output becomes 4+4=8
        clk_cycle(clk);
        check(address_out, x"00000008",
              "T02a: PC=4 (latched from reset), output=8",
              pcount, fcount);
        clk_cycle(clk);
        check(address_out, x"0000000C",
              "T02b: PC=8, output=0xC",
              pcount, fcount);
        clk_cycle(clk);
        check(address_out, x"00000010",
              "T02c: PC=0xC, output=0x10",
              pcount, fcount);
        clk_cycle(clk);
        check(address_out, x"00000014",
              "T02d: PC=0x10, output=0x14",
              pcount, fcount);

        -- =====================================================================
        -- T03: PC hold / NOP cycle (src=PC, offset_sel=2 -> 0)
        --      With offset=0, address_out = PC unchanged each cycle.
        -- =====================================================================
        test_num   <= 3;
        -- Re-issue reset to get known state: PC=0, then switch to zero offset.
        rst <= '1'; clk_cycle(clk);  -- PC latches 0 on reset edge
        offset_sel <= 2;         -- 0 offset
        src_sel    <= 0;
        rst <= '0';
        -- PC latches 0 on the last reset edge; with off=0 output stays 0
        clk_cycle(clk);
        check(address_out, x"00000000",
              "T03a: PC holds at 0x0 with zero offset",
              pcount, fcount);
        clk_cycle(clk);
        check(address_out, x"00000000",
              "T03b: PC still holds at 0x0",
              pcount, fcount);
        -- Now advance one step and then hold
        offset_sel <= 3;         -- +4
        clk_cycle(clk);          -- output=0+4=4, PC will latch 4 next edge
        offset_sel <= 2;         -- switch back to hold before next edge
        clk_cycle(clk);
        check(address_out, x"00000004",
              "T03c: PC=4 held with zero offset",
              pcount, fcount);
        clk_cycle(clk);
        check(address_out, x"00000004",
              "T03d: PC still 4 after second hold cycle",
              pcount, fcount);

        -- =====================================================================
        -- T04: BF/BT positive 8-bit displacement
        --      New PC = PC + sign_extend(disp8) << 1
        --      CU sign-extends disp8 and presents it on addr_off.
        --      PAU shifts left by 1 internally (offset_sel=0).
        --      Base address is current PC (src_sel=0).
        --
        --      Load PC = 0x00000100 via absolute jump first.
        -- =====================================================================
        test_num   <= 4;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        -- Absolute load: src=3 (zero), off=reg, addr_reg=0x100
        -- address_out = 0+0x100 = 0x100 immediately; PC latches 0x100 next edge
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00000100";
        pr_sel     <= 0;
        clk_cycle(clk);
        check(address_out, x"00000100",
              "T04 setup: PC loaded to 0x100",
              pcount, fcount);

        -- PC is now 0x100; apply BF with disp8=+0x10
        -- CU sign-extends 0x10 -> 0x00000010; PAU shifts -> 0x00000020
        -- address_out = 0x100 + 0x20 = 0x120
        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"00000010";
        wait for 1 ns;  -- wait for combinatorial to settle before checking
        check(address_out,
              add32(x"00000100", sext8_shl1(x"10")),
              "T04a: BF +0x10: PC=0x100, comb output=0x120",
              pcount, fcount);
        clk_cycle(clk);
        
        -- PC is now 0x120; apply disp8=+0x7E (max positive: +254 bytes)
        -- PAU shifts -> 0xFC; output = 0x120 + 0xFC = 0x21C
        addr_off   <= x"0000007E";
        wait for 1 ns;  -- wait for combinatorial to settle before checking
        check(address_out,
              add32(x"00000120", sext8_shl1(x"7E")),
              "T04b: BT +0x7E max-positive: PC=0x120, output=0x21C",
              pcount, fcount);
        clk_cycle(clk);
        

        -- =====================================================================
        -- T05: BF/BT negative 8-bit displacement (backward branch)
        -- =====================================================================
        test_num   <= 5;
        -- PC is now 0x21C; load clean base 0x200
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00000200";
        clk_cycle(clk);
        -- PC=0x200; disp8=0xFE -> sign-ext=-2 -> shift -> -4 (0xFFFFFFFC)
        -- output = 0x200 + 0xFFFFFFFC = 0x1FC
        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"FFFFFFFE";
        wait for 1 ns;  -- wait for combinatorial to settle before checking
        check(address_out,
              add32(x"00000200", x"FFFFFFFC"),
              "T05a: BF disp=-2 (0xFE): PC=0x200, output=0x1FC",
              pcount, fcount);
        clk_cycle(clk);
        
        
        -- PC=0x1FC; disp8=0x80 -> sign-ext=0xFFFFFF80=-128 -> shift=0xFFFFFF00
        -- output = 0x1FC + 0xFFFFFF00 = 0xFC
        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"FFFFFF80";
        wait for 1 ns;  -- wait for combinatorial to settle before checking
        check(address_out,
              add32(x"000001FC", x"FFFFFF00"),
              "T05b: BF disp=0x80 (min-negative): PC=0x1FC, output=0xFC",
              pcount, fcount);
        clk_cycle(clk);
        
        -- =====================================================================
        -- T06: BRA/BSR positive 12-bit displacement
        -- =====================================================================
        test_num   <= 6;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00001000";
        clk_cycle(clk);   -- PC latches to 0x1000

        -- disp12=0x100 -> sign-ext=0x100 -> shift=0x200
        -- output = 0x1000 + 0x200 = 0x1200
        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"00000100";
        wait for 1 ns;  -- wait for combinatorial to settle before checking
        check(address_out,
              add32(x"00001000", x"00000200"),
              "T06a: BRA disp12=+0x100: PC=0x1000, output=0x1200",
              pcount, fcount);
        clk_cycle(clk);
        -- PC=0x1200; disp12=0x3FE -> shift=0x7FC
        -- output = 0x1200 + 0x7FC = 0x19FC
        addr_off <= x"000003FE";
        wait for 1 ns;  -- wait for combinatorial to settle before checking
        check(address_out,
              add32(x"00001200", x"000007FC"),
              "T06b: BRA disp12=0x3FE: PC=0x1200, output=0x19FC",
              pcount, fcount);

        -- =====================================================================
        -- T07: BRA/BSR negative 12-bit displacement
        -- =====================================================================
        test_num   <= 7;
        clk_cycle(clk);
        -- PC=0x19FC; disp12=0xFFE -> sign-ext=0xFFFFFFFE -> shift=0xFFFFFFFC
        -- output = 0x19FC + 0xFFFFFFFC = 0x19F8
        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"FFFFFFFE";
        wait for 1 ns;  -- wait for combinatorial to settle before checking
        check(address_out,
              add32(x"000019FC", x"FFFFFFFC"),
              "T07a: BRA disp12=0xFFE (-2): PC=0x19FC, output=0x19F8",
              pcount, fcount);
        clk_cycle(clk);
        -- Load clean base 0x2000, then apply most-negative 12-bit disp
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00002000";
        clk_cycle(clk);   -- PC latches to 0x2000
        -- disp12=0x800 -> sign-ext=0xFFFFF800=-2048 -> shift=0xFFFFF000=-4096
        -- output = 0x2000 + 0xFFFFF000 = 0x1000
        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"FFFFF800";
        wait for 1 ns;  -- wait for combinatorial to settle before checking
        check(address_out,
              add32(x"00002000", x"FFFFF000"),
              "T07b: BRA disp12=0x800 (min-neg): PC=0x2000, output=0x1000",
              pcount, fcount);

        -- =====================================================================
        -- T08: Maximum positive 12-bit displacement
        --      disp12=0x7FF -> shift -> 0xFFE (+4094 bytes)
        -- =====================================================================
        test_num   <= 8;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00000000";
        clk_cycle(clk);   -- PC latches to 0

        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"000007FF";
        wait for 1 ns;  -- wait for combinatorial to settle before checking
        check(address_out,
              x"00000FFE",
              "T08: Max +12-bit disp: PC=0, output=0xFFE",
              pcount, fcount);

        -- =====================================================================
        -- T09: Maximum negative 12-bit displacement
        --      disp12=0x800 -> shift -> -4096
        -- =====================================================================
        test_num   <= 9;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00008000";
        clk_cycle(clk);   -- PC latches to 0x8000

        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"FFFFF800";
        wait for 1 ns;  -- wait for combinatorial to settle before checking
        check(address_out,
              x"00007000",
              "T09: Max -12-bit disp: PC=0x8000, output=0x7000",
              pcount, fcount);

        -- =====================================================================
        -- T10: BRAF / BSRF -- register offset added to current PC
        --      New PC = PC + Rm  (src=PC, offset_sel=1 -> addr_reg)
        -- =====================================================================
        test_num   <= 10;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00004000";
        clk_cycle(clk);   -- PC latches to 0x4000

        -- BRAF Rm=0x1234: output = 0x4000 + 0x1234 = 0x5234
        src_sel    <= 0;
        offset_sel <= 1;
        addr_reg   <= x"00001234";
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out,
              x"00005234",
              "T10a: BRAF Rm=0x1234: PC=0x4000, output=0x5234",
              pcount, fcount);
        clk_cycle(clk);
        -- PC=0x5234; BSRF Rm=0xFFFF0000 (wrapping backward)
        src_sel    <= 0;
        offset_sel <= 1;
        addr_reg   <= x"FFFF0000";
        wait for 1 ns;
        check(address_out,
              add32(x"00005234", x"FFFF0000"),
              "T10b: BSRF Rm=0xFFFF0000: PC=0x5234, output wraps",
              pcount, fcount);

        -- =====================================================================
        -- T11: JMP / absolute jump from register
        --      New PC = Rm  (src=3=zero, offset_sel=1=addr_reg)
        -- =====================================================================
        test_num   <= 11;
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"DEADBEEF";
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out,
              x"DEADBEEF",
              "T11a: JMP @Rm=0xDEADBEEF (combinatorial, before latch)",
              pcount, fcount);
        clk_cycle(clk);
        -- PC latched to 0xDEADBEEF; but we switch addr_reg to 0 now
        addr_reg <= x"00000000";
        wait for 1 ns;
        check(address_out,
              x"00000000",
              "T11b: JMP @Rm=0x0 absolute",
              pcount, fcount);
        clk_cycle(clk);
        addr_reg <= x"FFFFFFFF";
        wait for 1 ns;
        check(address_out,
              x"FFFFFFFF",
              "T11c: JMP @Rm=0xFFFFFFFF",
              pcount, fcount);

        -- =====================================================================
        -- T12: RTS -- return from subroutine
        --      New PC = PR + 4  (src=1=PR, offset_sel=3=+4)
        -- =====================================================================
        test_num <= 12;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        -- Load PC = 0x2000
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00002000";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0x2000

        -- BSR: pr_sel=1 saves current PC (0x2000) into PR,
        --      branch to 0x2800 (src=3, off=reg)
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00002800";
        pr_sel     <= 1;
        wait for 1 ns;
        check(address_out,
              x"00002800",
              "T12 setup: combinatorial output=0x2800 before latch",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x2800, PR latches 0x2000

        -- RTS: src=PR, off=+4 -> output = 0x2000 + 4 = 0x2004
        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out,
              x"00002004",
              "T12a: RTS output = PR+4 = 0x2004",
              pcount, fcount);
        clk_cycle(clk);

        -- Second verification: load PR=0x1000 via pr_sel=2, then RTS
        src_sel    <= 0;
        offset_sel <= 2;   -- hold PC
        addr_reg   <= x"00001000";
        pr_sel     <= 2;   -- PR <- addr_reg
        clk_cycle(clk);    -- PR latches 0x1000

        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out,
              x"00001004",
              "T12b: RTS with PR=0x1000 -> output=0x1004",
              pcount, fcount);

        -- =====================================================================
        -- T13: RTE -- return from exception
        --      New PC = datadata_src + 4  (src=2, offset_sel=3)
        -- =====================================================================
        test_num <= 13;
        datadata_src <= x"00003000";
        src_sel    <= 2;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out,
              x"00003004",
              "T13a: RTE databus=0x3000 -> output=0x3004",
              pcount, fcount);
        clk_cycle(clk);

        datadata_src <= x"FFFFFFF8";
        wait for 1 ns;
        check(address_out,
              x"FFFFFFFC",
              "T13b: RTE databus=0xFFFFFFF8 -> output=0xFFFFFFFC",
              pcount, fcount);

        -- =====================================================================
        -- T14: Interrupt / TRAPA vector fetch
        --      New PC = datadata_src  (src=2, offset_sel=2 -> 0 offset)
        -- =====================================================================
        test_num <= 14;
        datadata_src <= x"00010080";
        src_sel      <= 2;
        offset_sel   <= 2;
        pr_sel       <= 0;
        wait for 1 ns;
        check(address_out,
              x"00010080",
              "T14a: TRAPA vector 0x10080 (VBR+0x80)",
              pcount, fcount);
        clk_cycle(clk);

        datadata_src <= x"00000000";
        wait for 1 ns;
        check(address_out,
              x"00000000",
              "T14b: Interrupt vector at 0x0",
              pcount, fcount);
        clk_cycle(clk);

        datadata_src <= x"ABC00100";
        wait for 1 ns;
        check(address_out,
              x"ABC00100",
              "T14c: TRAPA VBR=0xABC00000 vector=0xABC00100",
              pcount, fcount);

        -- =====================================================================
        -- T15: pr_sel=1 -- current PC saved into PR (BSR / JSR link)
        -- =====================================================================
        test_num <= 15;
        rst <= '1'; clk_cycle(clk); rst <= '0';

        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"0000A000";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0xA000

        -- BSR: save PC=0xA000 into PR, branch to 0xB000
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"0000B000";
        pr_sel     <= 1;
        wait for 1 ns;
        check(address_out, x"0000B000",
              "T15 setup: output=0xB000 before latch",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0xB000, PR latches 0xA000

        -- RTS: output = PR+4 = 0xA000+4 = 0xA004
        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out,
              x"0000A004",
              "T15: pr_sel=1 saved 0xA000; RTS output=0xA004",
              pcount, fcount);

        -- =====================================================================
        -- T16: pr_sel=2 -- register value written into PR
        -- =====================================================================
        test_num <= 16;
        clk_cycle(clk);
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"0000C000";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0xC000

        -- Write 0x1234 into PR (off=0 holds PC at 0xC000)
        src_sel    <= 0;
        offset_sel <= 2;
        addr_reg   <= x"00001234";
        pr_sel     <= 2;
        clk_cycle(clk);   -- PR latches 0x1234

        -- RTS: output = PR+4 = 0x1234+4 = 0x1238
        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out,
              x"00001238",
              "T16: pr_sel=2 wrote 0x1234; RTS output=0x1238",
              pcount, fcount);

        -- =====================================================================
        -- T17: pr_sel=0 -- PR unchanged across non-link branches
        -- =====================================================================
        test_num <= 17;
        clk_cycle(clk);
        -- Write PR=0xFFFF via pr_sel=2
        src_sel    <= 0;
        offset_sel <= 2;
        addr_reg   <= x"0000FFFF";
        pr_sel     <= 2;
        clk_cycle(clk);   -- PR latches 0xFFFF

        -- Non-link branches: pr_sel=0 must leave PR alone
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00050000";
        pr_sel     <= 0;
        clk_cycle(clk);
        clk_cycle(clk);
        clk_cycle(clk);

        -- RTS: output = PR+4 = 0xFFFF+4 = 0x10003
        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out,
              x"00010003",
              "T17: pr_sel=0 kept PR=0xFFFF; RTS output=0x10003",
              pcount, fcount);

        -- =====================================================================
        -- T18: Zero offset with PR base (src=PR, offset_sel=0 -> output=PR)
        -- =====================================================================
        test_num <= 18;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        -- Load PR=0x5678 via pr_sel=2
        src_sel    <= 0;
        offset_sel <= 2;
        addr_reg   <= x"00005678";
        pr_sel     <= 2;
        clk_cycle(clk);   -- PR latches 0x5678

        src_sel    <= 1;
        offset_sel <= 2;   -- zero offset
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out,
              x"00005678",
              "T18: src=PR, off=0 -> output=PR=0x5678",
              pcount, fcount);

        -- =====================================================================
        -- T19: Sign extension -- large positive 8-bit displacement
        --      disp8=0x7F -> shift -> 0xFE (+254)
        -- =====================================================================
        test_num <= 19;
        clk_cycle(clk);
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00000100";
        clk_cycle(clk);   -- PC latches 0x100

        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"0000007F";
        wait for 1 ns;
        check(address_out,
              add32(x"00000100", x"000000FE"),
              "T19: disp8=0x7F shift -> 0xFE: PC=0x100, output=0x1FE",
              pcount, fcount);

        -- =====================================================================
        -- T20: Sign extension -- maximum negative 8-bit displacement
        --      disp8=0x80 -> sign-ext=0xFFFFFF80 -> shift -> 0xFFFFFF00
        -- =====================================================================
        test_num <= 20;
        clk_cycle(clk);
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00000500";
        clk_cycle(clk);   -- PC latches 0x500

        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"FFFFFF80";
        wait for 1 ns;
        check(address_out,
              add32(x"00000500", x"FFFFFF00"),
              "T20: disp8=0x80 (min-neg) shift -> -256: PC=0x500, output=0x400",
              pcount, fcount);

        -- =====================================================================
        -- T21: addr_reg large positive (BRAF far forward)
        -- =====================================================================
        test_num <= 21;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00001000";
        clk_cycle(clk);   -- PC latches 0x1000

        src_sel    <= 0;
        offset_sel <= 1;
        addr_reg   <= x"0FFFFFFF";
        wait for 1 ns;
        check(address_out,
              x"10000FFF",
              "T21: BRAF Rm=0x0FFFFFFF: PC=0x1000, output=0x10000FFF",
              pcount, fcount);
        clk_cycle(clk);

        -- =====================================================================
        -- T22: addr_reg large negative (BRAF far backward)
        -- =====================================================================
        test_num <= 22;
        -- PC=0x10000FFF; Rm=0x80000000 (wraps backward)
        src_sel    <= 0;
        offset_sel <= 1;
        addr_reg   <= x"80000000";
        wait for 1 ns;
        check(address_out,
              add32(x"10000FFF", x"80000000"),
              "T22: BRAF Rm=0x80000000: PC=0x10000FFF, output wraps",
              pcount, fcount);

        -- =====================================================================
        -- T23: datadata_src passthrough with zero offset
        -- =====================================================================
        test_num <= 23;
        datadata_src <= x"12345678";
        src_sel      <= 2;
        offset_sel   <= 2;
        pr_sel       <= 0;
        wait for 1 ns;
        check(address_out,
              x"12345678",
              "T23: databus passthrough + zero offset",
              pcount, fcount);

        -- =====================================================================
        -- T24: datadata_src passthrough with +4 offset (RTE pattern)
        -- =====================================================================
        test_num <= 24;
        datadata_src <= x"ABCD0000";
        src_sel      <= 2;
        offset_sel   <= 3;
        pr_sel       <= 0;
        wait for 1 ns;
        check(address_out,
              x"ABCD0004",
              "T24: RTE databus=0xABCD0000 +4 -> 0xABCD0004",
              pcount, fcount);

        -- =====================================================================
        -- T25: Sequential multi-cycle execution run
        --      Simulates: NOP, NOP, BRA, fetch, BSR, NOP-in-sub, RTS, fetch
        --      All checks are against combinatorial output = current_PC + offset.
        -- =====================================================================
        test_num <= 25;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00000000";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0x0

        -- PC=0x0; seq fetch output = 0+4 = 4
        src_sel    <= 0; offset_sel <= 3; pr_sel <= 0;
        wait for 1 ns;
        check(address_out, x"00000004",
              "T25-1: PC=0, output=4", pcount, fcount);
        clk_cycle(clk);   -- PC latches 4

        -- PC=4; output = 4+4 = 8
        check(address_out, x"00000008",
              "T25-2: PC=4, output=8", pcount, fcount);
        clk_cycle(clk);   -- PC latches 8

        -- PC=8; BRA +0x40: shift -> +0x80; output = 8+0x80 = 0x88
        src_sel    <= 0; offset_sel <= 0;
        addr_off   <= x"00000040";
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"00000088",
              "T25-3: PC=8, BRA +0x40 output=0x88", pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x88

        -- PC=0x88; seq fetch output = 0x88+4 = 0x8C
        src_sel    <= 0; offset_sel <= 3; pr_sel <= 0;
        wait for 1 ns;
        check(address_out, x"0000008C",
              "T25-4: PC=0x88, output=0x8C", pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x8C

        -- PC=0x8C; BSR +0x10: shift -> +0x20; output = 0x8C+0x20 = 0xAC
        --   pr_sel=1 -> PR will latch 0x8C on this edge
        src_sel    <= 0; offset_sel <= 0;
        addr_off   <= x"00000010";
        pr_sel     <= 1;
        wait for 1 ns;
        check(address_out, x"000000AC",
              "T25-5: PC=0x8C, BSR +0x10 output=0xAC", pcount, fcount);
        clk_cycle(clk);   -- PC latches 0xAC, PR latches 0x8C

        -- PC=0xAC; seq fetch output = 0xAC+4 = 0xB0
        src_sel    <= 0; offset_sel <= 3; pr_sel <= 0;
        wait for 1 ns;
        check(address_out, x"000000B0",
              "T25-6: PC=0xAC, output=0xB0", pcount, fcount);
        clk_cycle(clk);   -- PC latches 0xB0

        -- PC=0xB0; RTS: output = PR+4 = 0x8C+4 = 0x90
        src_sel    <= 1; offset_sel <= 3; pr_sel <= 0;
        wait for 1 ns;
        check(address_out, x"00000090",
              "T25-7: RTS output=PR+4=0x90", pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x90

        -- PC=0x90; seq fetch output = 0x90+4 = 0x94
        src_sel    <= 0; offset_sel <= 3; pr_sel <= 0;
        wait for 1 ns;
        check(address_out, x"00000094",
              "T25-8: PC=0x90, output=0x94", pcount, fcount);

        -- =====================================================================
        -- T26: Reset mid-execution
        --      During reset: PC=0; output depends on current src/offset.
        --      With off=+4: output = 0+4 = 4.
        --      With off=0:  output = 0+0 = 0.
        -- =====================================================================
        test_num <= 26;
        -- Switch to off=+4, then assert reset
        src_sel    <= 0; offset_sel <= 3; pr_sel <= 0;
        rst <= '1';
        clk_cycle(clk);
        -- Reset held, PC=0, off=+4 -> output=4
        check(address_out, x"00000004",
              "T26a: Reset held, off=+4 -> output=4 (PC forced 0)",
              pcount, fcount);
        -- Switch to off=0 while reset still held
        offset_sel <= 2;
        clk_cycle(clk);
        check(address_out, x"00000000",
              "T26b: Reset held, off=0 -> output=0",
              pcount, fcount);
        rst <= '0';

        -- =====================================================================
        -- T27: All-ones displacement (offset_sel=0, addr_off=0xFFFFFFFF)
        --      -1 sext, shift -> -2 (0xFFFFFFFE)
        -- =====================================================================
        test_num <= 27;
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00000010";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0x10

        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"FFFFFFFF";
        wait for 1 ns;
        check(address_out, x"0000000E",
              "T27: addr_off=0xFFFFFFFF (-1) shift -> -2: PC=0x10, output=0xE",
              pcount, fcount);

        -- =====================================================================
        -- T28: All-ones addr_reg (offset_sel=1, src=3=zero)
        --      output = 0 + 0xFFFFFFFF = 0xFFFFFFFF
        -- =====================================================================
        test_num <= 28;
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"FFFFFFFF";
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"FFFFFFFF",
              "T28: addr_reg=0xFFFFFFFF absolute jump output",
              pcount, fcount);

        -- =====================================================================
        -- T29: Wrap-around: PC=0xFFFFFFFF, offset=+4 wraps to 0x3
        -- =====================================================================
        test_num <= 29;
        clk_cycle(clk);   -- PC latches 0xFFFFFFFF
        src_sel    <= 0;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"00000003",
              "T29: PC=0xFFFFFFFF + 4 wraps to 0x3",
              pcount, fcount);

        -- =====================================================================
        -- T30: Branch to address 0 (reset vector via databus)
        -- =====================================================================
        test_num <= 30;
        datadata_src <= x"00000000";
        src_sel      <= 2;
        offset_sel   <= 2;
        pr_sel       <= 0;
        wait for 1 ns;
        check(address_out, x"00000000",
              "T30: Absolute jump to address 0x0 (reset vector)",
              pcount, fcount);

        -- =====================================================================
        -- Edge case tests
        -- =====================================================================

        -- E1: BRA with zero displacement -> output = PC + 0 = PC (no movement)
        test_num <= 31;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00000400";
        clk_cycle(clk);   -- PC latches 0x400

        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"00000000";
        wait for 1 ns;
        check(address_out, x"00000400",
              "E1: BRA disp=0: PC=0x400, output=0x400 (no movement)",
              pcount, fcount);

        -- E2: BSRF Rm=0 -> output = PC + 0 = PC
        test_num <= 32;
        src_sel    <= 0;
        offset_sel <= 1;
        addr_reg   <= x"00000000";
        pr_sel     <= 1;
        wait for 1 ns;
        check(address_out, x"00000400",
              "E2: BSRF Rm=0: PC=0x400, output=0x400",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x400, PR latches 0x400

        -- E3: PR save and immediate RTS round-trip
        test_num <= 33;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00008000";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0x8000

        -- JSR to 0x9000: save PC=0x8000 into PR
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00009000";
        pr_sel     <= 1;
        wait for 1 ns;
        check(address_out, x"00009000",
              "E3 setup: JSR output=0x9000", pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x9000, PR latches 0x8000

        -- Immediate RTS: output = PR+4 = 0x8004
        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"00008004",
              "E3: RTS output=PR+4=0x8004", pcount, fcount);

        -- E4: Double BSR: second BSR overwrites PR
        test_num <= 34;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00001000";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0x1000

        -- First BSR: PR <- 0x1000, jump to 0x2000
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00002000";
        pr_sel     <= 1;
        clk_cycle(clk);   -- PC latches 0x2000, PR latches 0x1000

        -- Second BSR: PR <- 0x2000, jump to 0x3000
        addr_reg   <= x"00003000";
        pr_sel     <= 1;
        clk_cycle(clk);   -- PC latches 0x3000, PR latches 0x2000

        -- RTS: output = PR+4 = 0x2000+4 = 0x2004
        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"00002004",
              "E4: Double BSR: RTS output=PR+4=0x2004",
              pcount, fcount);

        -- E5: PR=0xFFFFFFFF then RTS -> output wraps to 0x3
        test_num <= 35;
        clk_cycle(clk);
        src_sel    <= 0;
        offset_sel <= 2;
        addr_reg   <= x"FFFFFFFF";
        pr_sel     <= 2;
        clk_cycle(clk);   -- PR latches 0xFFFFFFFF

        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"00000003",
              "E5: PR=0xFFFFFFFF; PR+4 wraps to 0x3",
              pcount, fcount);

        -- E6: datadata_src near top of address space with +4 wraps to 0
        test_num <= 36;
        datadata_src <= x"FFFFFFFC";
        src_sel      <= 2;
        offset_sel   <= 3;
        pr_sel       <= 0;
        wait for 1 ns;
        check(address_out, x"00000000",
              "E6: databus=0xFFFFFFFC + 4 wraps to 0x0",
              pcount, fcount);

        -- E7: Reset interleaved -- output during reset reflects PC=0
        test_num <= 37;
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"0000CAFE";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0xCAFE

        -- Assert reset: PC forced to 0; with off=reg(0xCAFE), output = 0+0xCAFE
        rst <= '1';
        wait for 1 ns;
        check(address_out, x"0000CAFE",
              "E7a: Reset asserted but comb output still shows 0+reg=0xCAFE",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0 (reset overrides)
        -- Now PC=0; output = 0+0xCAFE = 0xCAFE still (addr_reg unchanged)
        -- Switch to off=+4 to confirm PC=0
        offset_sel <= 3;
        wait for 1 ns;
        check(address_out, x"00000004",
              "E7b: After reset clk edge, PC=0, off=+4 -> output=4",
              pcount, fcount);
        rst <= '0';
        clk_cycle(clk);   -- PC latches 4

        src_sel <= 0;
        wait for 1 ns;
        check(address_out, x"00000008",
              "E7c: rst released, PC=4, output=8 (normal fetch)",
              pcount, fcount);

        -- =====================================================================
        -- E8: BRAF with negative and boundary register offsets
        --     src=PC (0), offset_sel=1 (addr_reg), covers near-zero, large-neg,
        --     and Rm=1 (minimal positive) offset cases.
        -- =====================================================================
        test_num <= 38;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        -- Load PC=0x00010000
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00010000";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0x10000

        -- BRAF Rm=0xFFFFFFFF (-1): output = 0x10000 + 0xFFFFFFFF = 0x0000FFFF
        src_sel    <= 0;
        offset_sel <= 1;
        addr_reg   <= x"FFFFFFFF";
        wait for 1 ns;
        check(address_out,
              add32(x"00010000", x"FFFFFFFF"),
              "E8a: BRAF Rm=-1: PC=0x10000, output=0xFFFF",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0xFFFF

        -- BRAF Rm=0x80000000 (most-negative signed): output wraps
        addr_reg   <= x"80000000";
        wait for 1 ns;
        check(address_out,
              add32(x"0000FFFF", x"80000000"),
              "E8b: BRAF Rm=0x80000000: PC=0xFFFF, output wraps to 0x80000FFF",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches wrapped value

        -- Load a clean base, then BRAF Rm=1 (odd result -- PAU does no alignment)
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00004000";
        clk_cycle(clk);   -- PC latches 0x4000
        src_sel    <= 0;
        addr_reg   <= x"00000001";
        wait for 1 ns;
        check(address_out,
              x"00004001",
              "E8c: BRAF Rm=1: PC=0x4000, output=0x4001 (odd addr)",
              pcount, fcount);

        -- BRAF Rm=0: output = PC + 0 = PC (no movement)
        addr_reg   <= x"00000000";
        wait for 1 ns;
        check(address_out,
              x"00004000",
              "E8d: BRAF Rm=0: PC=0x4000, output=0x4000 (no movement)",
              pcount, fcount);

        -- =====================================================================
        -- E9: Zero offset (offset_sel=2) across all four src_sel values
        --     Confirms each source passes through unmodified.
        -- =====================================================================
        test_num <= 39;
        rst <= '1'; clk_cycle(clk); rst <= '0';

        -- Load PC=0x1234 via absolute jump, then load PR=0x5678
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00001234";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0x1234

        src_sel    <= 0;
        offset_sel <= 2;   -- hold PC
        addr_reg   <= x"00005678";
        pr_sel     <= 2;   -- PR <- 0x5678
        clk_cycle(clk);   -- PR latches 0x5678

        -- src=PC (0), off=0: output = PC = 0x1234
        src_sel    <= 0;
        offset_sel <= 2;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"00001234",
              "E9a: src=PC, off=0 -> output=PC=0x1234",
              pcount, fcount);

        -- src=PR (1), off=0: output = PR = 0x5678
        src_sel    <= 1;
        wait for 1 ns;
        check(address_out, x"00005678",
              "E9b: src=PR, off=0 -> output=PR=0x5678",
              pcount, fcount);

        -- src=databus (2), off=0: output = databus
        datadata_src <= x"CAFEBABE";
        src_sel    <= 2;
        wait for 1 ns;
        check(address_out, x"CAFEBABE",
              "E9c: src=databus, off=0 -> output=0xCAFEBABE",
              pcount, fcount);

        -- src=zero (3), off=0: output = 0
        src_sel    <= 3;
        wait for 1 ns;
        check(address_out, x"00000000",
              "E9d: src=zero, off=0 -> output=0",
              pcount, fcount);

        -- =====================================================================
        -- E10: BF/BT displacement extremes -- boundary values for offset_sel=0
        --      addr_off is the 32-bit sign-extended displacement;
        --      PAU shifts left by 1 internally.
        -- =====================================================================
        test_num <= 40;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        -- Load PC=0x00002000
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00002000";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0x2000

        -- disp=+1: addr_off=0x1, PAU shifts -> 0x2; output = 0x2000+2 = 0x2002
        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"00000001";
        wait for 1 ns;
        check(address_out,
              add32(x"00002000", sext8_shl1(x"01")),
              "E10a: BF disp=+1: PC=0x2000, output=0x2002",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x2002

        -- disp=0xFF (-1 signed): addr_off=0xFFFFFFFF, PAU shifts -> 0xFFFFFFFE;
        -- output = 0x2002 + (-2) = 0x2000
        addr_off   <= x"FFFFFFFF";
        wait for 1 ns;
        check(address_out,
              add32(x"00002002", sext8_shl1(x"FF")),
              "E10b: BF disp=0xFF (-1): PC=0x2002, output=0x2000",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x2000

        -- disp=+0x7F (max positive 8-bit): shift -> 0xFE; output = 0x2000+0xFE = 0x20FE
        addr_off   <= x"0000007F";
        wait for 1 ns;
        check(address_out,
              add32(x"00002000", sext8_shl1(x"7F")),
              "E10c: BF disp=0x7F (max-pos): PC=0x2000, output=0x20FE",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x20FE

        -- disp=0x80 (most negative, -128): addr_off=0xFFFFFF80, shift -> 0xFFFFFF00;
        -- output = 0x20FE + (-256) = 0x1FFE
        addr_off   <= x"FFFFFF80";
        wait for 1 ns;
        check(address_out,
              add32(x"000020FE", sext8_shl1(x"80")),
              "E10d: BF disp=0x80 (min=-128): PC=0x20FE, output=0x1FFE",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x1FFE

        -- disp=+0x02 (small even): shift -> 0x04; output = 0x1FFE+4 = 0x2002
        addr_off   <= x"00000002";
        wait for 1 ns;
        check(address_out,
              add32(x"00001FFE", sext8_shl1(x"02")),
              "E10e: BF disp=+2: PC=0x1FFE, output=0x2002",
              pcount, fcount);

        -- =====================================================================
        -- E11: BRA/BSR 12-bit wrap-around at 32-bit address boundary
        --      PC placed near 0xFFFFFFFF; forward and backward branches that
        --      cross the 32-bit wrap point.
        -- =====================================================================
        test_num <= 41;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        -- Load PC=0xFFFFF000
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"FFFFF000";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0xFFFFF000

        -- BRA disp12=0x7FF (max +4094 bytes): addr_off=0x000007FF, shift -> 0xFFE
        -- output = 0xFFFFF000 + 0xFFE = 0xFFFFFFFE
        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"000007FF";
        wait for 1 ns;
        check(address_out,
              add32(x"FFFFF000", x"00000FFE"),
              "E11a: BRA max+12 near top: PC=0xFFFFF000, output=0xFFFFFFFE",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0xFFFFFFFE

        -- BRA disp=+2: addr_off=0x2, shift -> 0x4; 0xFFFFFFFE+4 wraps to 0x2
        addr_off   <= x"00000002";
        wait for 1 ns;
        check(address_out,
              add32(x"FFFFFFFE", x"00000004"),
              "E11b: BRA disp=+2 wrap: PC=0xFFFFFFFE, output=0x00000002",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x2

        -- BRA disp12=0x800 (min -4096): addr_off=0xFFFFF800, shift -> 0xFFFFF000
        -- output = 0x2 + (-4096) = 0xFFFFF002
        addr_off   <= x"FFFFF800";
        wait for 1 ns;
        check(address_out,
              add32(x"00000002", x"FFFFF000"),
              "E11c: BRA min-neg wraps backward: PC=0x2, output=0xFFFFF002",
              pcount, fcount);

        -- =====================================================================
        -- E12: PR edge cases for RTS
        --      PR=0, PR near max (wraps to 0), PR=0x80000000, PR=odd.
        -- =====================================================================
        test_num <= 42;
        rst <= '1'; clk_cycle(clk); rst <= '0';

        -- PR=0 after reset; RTS: output = PR+4 = 4
        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"00000004",
              "E12a: PR=0 (post-reset), RTS -> PR+4=4",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 4

        -- Load PR=0xFFFFFFFC; RTS -> 0xFFFFFFFC+4 wraps to 0
        src_sel    <= 0;
        offset_sel <= 2;
        addr_reg   <= x"FFFFFFFC";
        pr_sel     <= 2;
        clk_cycle(clk);   -- PR latches 0xFFFFFFFC

        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"00000000",
              "E12b: PR=0xFFFFFFFC, RTS -> PR+4 wraps to 0x0",
              pcount, fcount);
        clk_cycle(clk);

        -- Load PR=0x80000000; RTS -> 0x80000004
        src_sel    <= 0;
        offset_sel <= 2;
        addr_reg   <= x"80000000";
        pr_sel     <= 2;
        clk_cycle(clk);   -- PR latches 0x80000000

        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"80000004",
              "E12c: PR=0x80000000, RTS -> PR+4=0x80000004",
              pcount, fcount);
        clk_cycle(clk);

        -- Load PR=0x00000001 (odd address); RTS -> 5
        src_sel    <= 0;
        offset_sel <= 2;
        addr_reg   <= x"00000001";
        pr_sel     <= 2;
        clk_cycle(clk);   -- PR latches 0x1

        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"00000005",
              "E12d: PR=0x1, RTS -> PR+4=0x5 (odd -- PAU has no alignment check)",
              pcount, fcount);

        -- =====================================================================
        -- E13: Consecutive sequential fetches -- 6-step run from known base
        --      PC=0x1000; each cycle advances by 4; verify every step.
        -- =====================================================================
        test_num <= 43;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00001000";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0x1000

        src_sel    <= 0;
        offset_sel <= 3;   -- +4
        wait for 1 ns;
        check(address_out, x"00001004",
              "E13a: PC=0x1000, output=0x1004", pcount, fcount);
        clk_cycle(clk);
        check(address_out, x"00001008",
              "E13b: PC=0x1004, output=0x1008", pcount, fcount);
        clk_cycle(clk);
        check(address_out, x"0000100C",
              "E13c: PC=0x1008, output=0x100C", pcount, fcount);
        clk_cycle(clk);
        check(address_out, x"00001010",
              "E13d: PC=0x100C, output=0x1010", pcount, fcount);
        clk_cycle(clk);
        check(address_out, x"00001014",
              "E13e: PC=0x1010, output=0x1014", pcount, fcount);
        clk_cycle(clk);
        check(address_out, x"00001018",
              "E13f: PC=0x1014, output=0x1018", pcount, fcount);

        -- =====================================================================
        -- E14: src_sel=3 (zero base) with all four offset_sel values
        --      output = 0 + offset in each case.
        -- =====================================================================
        test_num <= 44;

        -- offset_sel=0 (shifted disp): addr_off=0x10, shift -> 0x20; output=0x20
        src_sel    <= 3;
        offset_sel <= 0;
        addr_off   <= x"00000010";
        wait for 1 ns;
        check(address_out, x"00000020",
              "E14a: src=zero, off=disp(0x10<<1)=0x20, output=0x20",
              pcount, fcount);

        -- offset_sel=1 (addr_reg): output = 0 + addr_reg
        offset_sel <= 1;
        addr_reg   <= x"12345678";
        wait for 1 ns;
        check(address_out, x"12345678",
              "E14b: src=zero, off=reg=0x12345678, output=0x12345678",
              pcount, fcount);

        -- offset_sel=2 (zero): output = 0 + 0 = 0
        offset_sel <= 2;
        wait for 1 ns;
        check(address_out, x"00000000",
              "E14c: src=zero, off=0 -> output=0",
              pcount, fcount);

        -- offset_sel=3 (+4): output = 0 + 4 = 4
        offset_sel <= 3;
        wait for 1 ns;
        check(address_out, x"00000004",
              "E14d: src=zero, off=+4 -> output=4",
              pcount, fcount);

        -- =====================================================================
        -- E15: pr_sel transitions -- load, hold, overwrite, verify no bleed
        --      Tests that PR stores the right value and pr_sel=0 never alters it.
        -- =====================================================================
        test_num <= 45;
        rst <= '1'; clk_cycle(clk); rst <= '0';

        -- Load PC=0x3000; then pr_sel=1 saves PC=0x3000 into PR during hold cycle
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00003000";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0x3000

        src_sel    <= 0;
        offset_sel <= 2;   -- hold PC
        pr_sel     <= 1;   -- PR <- current PC = 0x3000
        clk_cycle(clk);   -- PR latches 0x3000

        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"00003004",
              "E15a: pr_sel=1 saved PC=0x3000; RTS -> 0x3004",
              pcount, fcount);

        -- Overwrite PR with 0xABCD via pr_sel=2
        clk_cycle(clk);   -- PC latches 0x3004
        src_sel    <= 0;
        offset_sel <= 2;
        addr_reg   <= x"0000ABCD";
        pr_sel     <= 2;
        clk_cycle(clk);   -- PR latches 0xABCD

        -- RTS: output = 0xABCD + 4 = 0xABD1
        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"0000ABD1",
              "E15b: pr_sel=2 wrote 0xABCD; RTS -> 0xABD1",
              pcount, fcount);

        -- Run 4 cycles with pr_sel=0; PR must remain 0xABCD
        clk_cycle(clk);
        src_sel    <= 0;
        offset_sel <= 3;
        pr_sel     <= 0;
        clk_cycle(clk);
        clk_cycle(clk);
        clk_cycle(clk);

        src_sel    <= 1;
        offset_sel <= 3;
        wait for 1 ns;
        check(address_out, x"0000ABD1",
              "E15c: pr_sel=0 held PR=0xABCD across 4 cycles; RTS still -> 0xABD1",
              pcount, fcount);

        -- =====================================================================
        -- E16: src=PR, offset=shifted displacement (PR-relative branch path)
        --      output = PR + (addr_off << 1)
        -- =====================================================================
        test_num <= 46;
        rst <= '1'; clk_cycle(clk); rst <= '0';

        -- Load PR=0x00004000 via pr_sel=2 (PC stays 0)
        src_sel    <= 0;
        offset_sel <= 2;
        addr_reg   <= x"00004000";
        pr_sel     <= 2;
        clk_cycle(clk);   -- PR latches 0x4000

        -- src=PR, off=disp(0x40<<1=0x80): output = 0x4000 + 0x80 = 0x4080
        src_sel    <= 1;
        offset_sel <= 0;
        addr_off   <= x"00000040";
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out, x"00004080",
              "E16a: src=PR=0x4000, disp(0x40<<1)=0x80 -> output=0x4080",
              pcount, fcount);

        -- Negative shifted disp: addr_off=0xFFFFFFFF (-1), shift -> 0xFFFFFFFE (-2)
        -- output = 0x4000 + (-2) = 0x3FFE
        addr_off   <= x"FFFFFFFF";
        wait for 1 ns;
        check(address_out,
              add32(x"00004000", x"FFFFFFFE"),
              "E16b: src=PR=0x4000, disp(-1<<1)=-2 -> output=0x3FFE",
              pcount, fcount);

        -- Large positive: addr_off=0x00007FFF, shift -> 0xFFFE
        -- output = 0x4000 + 0xFFFE = 0x13FFE
        addr_off   <= x"00007FFF";
        wait for 1 ns;
        check(address_out,
              add32(x"00004000", x"0000FFFE"),
              "E16c: src=PR=0x4000, disp(0x7FFF<<1)=0xFFFE -> output=0x13FFE",
              pcount, fcount);

        -- =====================================================================
        -- E17: BRA/BSR 12-bit mid-range: additional coverage beyond boundary tests
        -- =====================================================================
        test_num <= 47;
        rst <= '1'; clk_cycle(clk); rst <= '0';
        -- Load PC=0x00010000
        src_sel    <= 3;
        offset_sel <= 1;
        addr_reg   <= x"00010000";
        pr_sel     <= 0;
        clk_cycle(clk);   -- PC latches 0x10000

        -- BRA disp12=+0x200: addr_off=0x200, shift -> 0x400
        -- output = 0x10000 + 0x400 = 0x10400
        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"00000200";
        wait for 1 ns;
        check(address_out,
              add32(x"00010000", x"00000400"),
              "E17a: BRA disp=+0x200 shift->0x400: PC=0x10000, output=0x10400",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x10400

        -- BRA disp12=0xFFFFFFFE (-2, shift -> -4): output = 0x10400 + (-4) = 0x103FC
        addr_off   <= x"FFFFFFFE";
        wait for 1 ns;
        check(address_out,
              add32(x"00010400", x"FFFFFFFC"),
              "E17b: BRA disp=-2 shift->-4: PC=0x10400, output=0x103FC",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x103FC

        -- BRA disp12=+0x100: addr_off=0x100, shift -> 0x200
        -- output = 0x103FC + 0x200 = 0x105FC
        addr_off   <= x"00000100";
        wait for 1 ns;
        check(address_out,
              add32(x"000103FC", x"00000200"),
              "E17c: BRA disp=+0x100 shift->0x200: PC=0x103FC, output=0x105FC",
              pcount, fcount);
        clk_cycle(clk);

        -- BSR with pr_sel=1: saves PC=0x105FC, branches forward by 0x3FF<<1=0x7FE
        -- output = 0x105FC + 0x7FE = 0x10DFA
        src_sel    <= 0;
        offset_sel <= 0;
        addr_off   <= x"000003FF";
        pr_sel     <= 1;
        wait for 1 ns;
        check(address_out,
              add32(x"000105FC", x"000007FE"),
              "E17d: BSR disp=0x3FF shift->0x7FE: PC=0x105FC, output=0x10DFA",
              pcount, fcount);
        clk_cycle(clk);   -- PC latches 0x10DFA, PR latches 0x105FC

        -- RTS: output = PR + 4 = 0x105FC + 4 = 0x10600
        src_sel    <= 1;
        offset_sel <= 3;
        pr_sel     <= 0;
        wait for 1 ns;
        check(address_out,
              x"00010600",
              "E17e: RTS after BSR: PR=0x105FC, output=0x10600",
              pcount, fcount);

        -- =====================================================================
        -- Final summary
        -- =====================================================================
        wait for CLK_PERIOD * 2;

        report "========================================================"
            severity note;
        report "  PAUSH2 TEST BENCH COMPLETE"
            severity note;
        report "  PASSED : " & integer'image(pcount)
            severity note;
        report "  FAILED : " & integer'image(fcount)
            severity note;
        report "========================================================"
            severity note;

        if fcount = 0 then
            report "ALL TESTS PASSED" severity note;
        else
            report integer'image(fcount) & " TEST(S) FAILED"
                severity failure;
        end if;

        wait;
    end process stimulus;

end architecture behav;