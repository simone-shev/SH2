-- =============================================================================
-- tb_DAUSH2.vhd
-- Comprehensive Testbench for the SH-2 Data Address Unit (DAUSH2)
--
-- Entity Under Test: DAUSH2
-- Description:
--   The DAU generates effective addresses for SH-2 data memory accesses.
--   It selects an address source (Reg, GBR, VBR, PC), optionally adds a
--   shifted offset (from instruction immediate or R0), and supports
--   post-increment and pre-decrement of the base register.
--
--
-- SH-2 Addressing Modes covered (ref: SH-2 Programming Manual, Table 4.7):
--   TC-01  : Indirect register                         @Rn
--   TC-02  : Post-increment indirect register          @Rn+  (byte)
--   TC-03  : Post-increment indirect register          @Rn+  (word)
--   TC-04  : Post-increment indirect register          @Rn+  (longword)
--   TC-05  : Pre-decrement indirect register           @-Rn  (byte)
--   TC-06  : Pre-decrement indirect register           @-Rn  (word)
--   TC-07  : Pre-decrement indirect register           @-Rn  (longword)
--   TC-08  : Indirect register + displacement (byte)   @(disp,Rn) x1
--   TC-09  : Indirect register + displacement (word)   @(disp,Rn) x2
--   TC-10  : Indirect register + displacement (lword)  @(disp,Rn) x4
--   TC-11  : Indirect indexed register                 @(R0,Rn)
--   TC-12  : Indirect GBR + displacement (byte)        @(disp,GBR) x1
--   TC-13  : Indirect GBR + displacement (word)        @(disp,GBR) x2
--   TC-14  : Indirect GBR + displacement (lword)       @(disp,GBR) x4
--   TC-15  : Indirect indexed GBR                      @(R0,GBR)
--   TC-16  : PC-relative displacement (word)           @(disp,PC) x2
--   TC-17  : PC-relative displacement (lword)          @(disp,PC) x4  (PC & FFFC)
--   TC-18  : GBR load via internal register strobe
--   TC-19  : VBR load via internal register strobe
--   TC-20  : src_sel=2 (VBR) indirect addressing
--   TC-21  : Post-increment with R0 as index (offset_reg path)
--   TC-22  : Zero displacement (offset = 0)
--   TC-23  : Maximum 8-bit displacement with GBR (byte, word, lword)
--   TC-24  : Maximum 4-bit displacement with Rn  (byte, word, lword)
--   TC-25  : Address wrap-around (32-bit overflow)
--   TC-26  : Pre-decrement using GBR as base (STC.L GBR,@-Rn equivalent)
--   TC-27  : Post-increment using R0 as indexed offset source
--   TC-28  : src_sel=3 (PC) displaced access [requires BUG-001 fix]
--   TC-29  : Consecutive post-increments (sequential MOV.L @Rm+,Rn)
--   TC-30  : Consecutive pre-decrements  (sequential MOV.L Rm,@-Rn)
--   TC-31  : Power-on reset — VBR initialised to H'00000000 (SH-2 Table 2.1)
--   TC-32  : Reset clears a previously loaded VBR back to H'00000000
--   TC-33  : Reset does not disturb external Reg source (addr_reg input)
--   TC-34  : VBR + zero displacement via shifter = H'00000000 after reset
--
-- Reset signal:
--   reset : in std_logic  — active-high, synchronous (sampled on rising clock
--           edge).  Per SH-2 spec Table 2.1, only VBR is defined after reset
--           (H'00000000).  GBR is undefined; no GBR value is checked post-reset.
--
-- Revision History:
--     13 Apr 26  Claude Code       Initial revision
--     14 Apr 26  Simone Shevchuk   Changing pre/post, test comments match SH-2 spec, NOT MAU
--     15 Apr 26  Claude Code       Added additional tests
--     16 Apr 26  Simone Shevchuk   Comments updated
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_DAUSH2 is
end entity tb_DAUSH2;

architecture sim of tb_DAUSH2 is

    -- -------------------------------------------------------------------------
    -- Component declaration
    -- -------------------------------------------------------------------------
    component DAUSH2 is
        port(
            addr_PC      : in  std_logic_vector(31 downto 0);
            addr_reg     : in  std_logic_vector(31 downto 0);
            src_sel      : in  integer range 3 downto 0;  
            shift_sel    : in  integer range 2 downto 0;
            offset_ins   : in  std_logic_vector(31 downto 0);
            offset_reg   : in  std_logic_vector(31 downto 0);
            offset_sel   : in  integer range 1 downto 0;
            inc_dec_sel  : in  std_logic;
            inc_dec_bit  : in  integer range 31 downto 0;
            pre_post_sel : in  std_logic;
            clock        : in  std_logic;
            -- Active-high synchronous reset.
            -- Per SH-2 spec (Table 2.1): resets VBR to H'00000000.
            -- GBR is undefined after reset; no GBR output check is performed.
            reset        : in  std_logic;
            gbr_write     : in  std_logic;
            vbr_write     : in  std_logic;
            address_out  : out std_logic_vector(31 downto 0);
            addr_src_out : out std_logic_vector(31 downto 0)
        );
    end component;

    -- -------------------------------------------------------------------------
    -- Testbench signals
    -- -------------------------------------------------------------------------
    signal clk          : std_logic := '0';
    signal addr_PC      : std_logic_vector(31 downto 0) := (others => '0');
    signal addr_reg     : std_logic_vector(31 downto 0) := (others => '0');
    signal src_sel      : integer range 3 downto 0 := 0;
    signal shift_sel    : integer range 2 downto 0 := 0;
    signal offset_ins   : std_logic_vector(31 downto 0) := (others => '0');
    signal offset_reg   : std_logic_vector(31 downto 0) := (others => '0');
    signal offset_sel   : integer range 1 downto 0 := 0;
    signal inc_dec_sel  : std_logic := '0';
    signal inc_dec_bit  : integer range 31 downto 0 := 0;
    signal pre_post_sel : std_logic := '0';
    signal reset        : std_logic := '0';   -- active-high synchronous reset
    signal gbr_write     : std_logic := '0';   
    signal vbr_write     : std_logic := '0';   
    signal address_out  : std_logic_vector(31 downto 0);
    signal addr_src_out : std_logic_vector(31 downto 0);

    -- -------------------------------------------------------------------------
    -- Helpers
    -- -------------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;

    -- Convenience: convert integer to SLV(31:0)
    function to_slv32(val : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_signed(val, 32));
    end function;

    function to_slv32u(val : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(val, 32));
    end function;

    -- -------------------------------------------------------------------------
    -- VHDL-2008 protected type for thread-safe pass/fail counters.
    -- A plain shared variable is not legal in VHDL-2008 unless it is of a
    -- protected type (IEEE Std 1076-2008, section 6.6.2).
    -- -------------------------------------------------------------------------
    type t_test_counters is protected
        procedure increment_pass;
        procedure increment_fail;
        impure function get_pass return integer;
        impure function get_fail return integer;
    end protected t_test_counters;

    type t_test_counters is protected body
        variable v_pass : integer := 0;
        variable v_fail : integer := 0;

        procedure increment_pass is
        begin
            v_pass := v_pass + 1;
        end procedure;

        procedure increment_fail is
        begin
            v_fail := v_fail + 1;
        end procedure;

        impure function get_pass return integer is
        begin
            return v_pass;
        end function;

        impure function get_fail return integer is
        begin
            return v_fail;
        end function;
    end protected body t_test_counters;

    -- Single shared instance of the protected counter (VHDL-2008 compliant)
    shared variable test_counters : t_test_counters;

    -- -------------------------------------------------------------------------
    -- Procedure: check address_out
    -- -------------------------------------------------------------------------
    procedure check_addr(
        tc_id    : in string;
        expected : in std_logic_vector(31 downto 0)
    ) is begin
        if address_out = expected then
            report tc_id & " [PASS] address_out = 0x"
                & to_hstring(address_out) severity note;
            test_counters.increment_pass;
        else
            report tc_id & " [FAIL] address_out: got 0x"
                & to_hstring(address_out) & "  expected 0x"
                & to_hstring(expected) severity error;
            test_counters.increment_fail;
        end if;
    end procedure;

    -- -------------------------------------------------------------------------
    -- Procedure: check addr_src_out (updated base register)
    -- -------------------------------------------------------------------------
    procedure check_src(
        tc_id    : in string;
        expected : in std_logic_vector(31 downto 0)
    ) is begin
        if addr_src_out = expected then
            report tc_id & " [PASS] addr_src_out = 0x"
                & to_hstring(addr_src_out) severity note;
            test_counters.increment_pass;
        else
            report tc_id & " [FAIL] addr_src_out: got 0x"
                & to_hstring(addr_src_out) & "  expected 0x"
                & to_hstring(expected) severity error;
            test_counters.increment_fail;
        end if;
    end procedure;

begin

    -- -------------------------------------------------------------------------
    -- Clock generation
    -- -------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    -- -------------------------------------------------------------------------
    -- DUT instantiation
    -- -------------------------------------------------------------------------
    DUT : DAUSH2
        port map(
            addr_PC      => addr_PC,
            addr_reg     => addr_reg,
            src_sel      => src_sel,
            shift_sel    => shift_sel,
            offset_ins   => offset_ins,
            offset_reg   => offset_reg,
            offset_sel   => offset_sel,
            inc_dec_sel  => inc_dec_sel,
            inc_dec_bit  => inc_dec_bit,
            pre_post_sel => pre_post_sel,
            clock        => clk,
            reset        => reset,
            gbr_write     => gbr_write,
            vbr_write     => vbr_write,
            address_out  => address_out,
            addr_src_out => addr_src_out
        );

    -- =========================================================================
    -- Stimulus process
    -- =========================================================================
    stim : process is

        -- Helper: single rising-edge tick then settle
        procedure tick is begin
            wait until rising_edge(clk);
            wait for 1 ns;  -- small delta for combinational outputs to settle
        end procedure;

        -- Helper: assert active-high synchronous reset for one clock cycle.
        -- Per SH-2 spec Table 2.1, reset drives VBR to H'00000000.
        -- GBR is undefined after reset (spec does not constrain it).
        procedure do_reset is begin
            reset <= '1';
            tick;           -- reset is sampled on this rising edge
            reset <= '0';
        end procedure;

        -- Helper: load GBR with a value (requires ASSUME-001 ports)
        procedure load_GBR(val : std_logic_vector(31 downto 0)) is begin
            addr_reg <= val;
            gbr_write <= '1';
            tick;
            gbr_write <= '0';
        end procedure;

        -- Helper: load VBR with a value (requires ASSUME-001 ports)
        procedure load_VBR(val : std_logic_vector(31 downto 0)) is begin
            addr_reg <= val;
            vbr_write <= '1';
            tick;
            vbr_write <= '0';
        end procedure;

    begin
        -- =====================================================================
        -- Initialise all inputs to safe defaults, then apply synchronous reset.
        -- Reset is held for two clock cycles to guarantee the synchronous
        -- capture regardless of any initial metastability.
        -- =====================================================================
        addr_PC      <= (others => '0');
        addr_reg     <= (others => '0');
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= (others => '0');
        offset_reg   <= (others => '0');
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '1';
        gbr_write     <= '0';
        vbr_write     <= '0';
        reset        <= '0';
        -- Wait for two full clock cycles before asserting reset so the clock
        -- is running cleanly when the first rising edge is sampled.
        wait for CLK_PERIOD * 2;

        -- =====================================================================
        -- TC-31: Power-on reset — VBR must be H'00000000 after reset
        -- SH-2 spec Table 2.1: "VBR: H'00000000" after reset.
        -- Procedure:
        --   1. Assert reset = '1' for one clock cycle.
        --   2. Deassert reset = '0'.
        --   3. Select VBR as address source with zero offset.
        --   4. address_out must equal H'00000000.
        -- =====================================================================
        report "========================================" severity note;
        report "TC-31: Power-on reset - VBR = H'00000000" severity note;
        do_reset;
        -- Now drive src_sel = 2 (VBR) with no offset; combinational output
        -- should immediately reflect the reset value of VBR.
        src_sel      <= 2;          -- VBR
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';
        wait for 1 ns;
        check_addr("TC-31", x"00000000");

        -- =====================================================================
        -- TC-32: Reset clears a previously loaded VBR back to H'00000000
        -- Procedure:
        --   1. Load VBR with H'A000_0000 via vbr_write strobe.
        --   2. Verify VBR is visible as H'A000_0000 on address_out.
        --   3. Assert synchronous reset for one cycle.
        --   4. Verify address_out (VBR source) returns to H'00000000.
        -- =====================================================================
        report "---" severity note;
        report "TC-32: Reset clears loaded VBR back to H'00000000" severity note;
        -- Step 1-2: Load and verify VBR = A0000000
        load_VBR(x"A0000000");
        src_sel      <= 2;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';
        wait for 1 ns;
        check_addr("TC-32-pre-reset", x"A0000000");
        -- Step 3-4: Apply reset, VBR must return to 0
        do_reset;
        src_sel      <= 2;
        wait for 1 ns;
        check_addr("TC-32-post-reset", x"00000000");

        -- =====================================================================
        -- TC-33: Reset does not affect Reg-based addressing (addr_reg is an
        -- external input, not an internal register, so reset cannot change it).
        -- Procedure:
        --   1. Set addr_reg = H'1234_5678, src_sel = 0 (Reg).
        --   2. Apply reset.
        --   3. address_out must still equal H'1234_5678 — reset only clears
        --      VBR; it has no defined effect on the external Reg input.
        -- =====================================================================
        report "---" severity note;
        report "TC-33: Reset does not disturb external Reg source" severity note;
        addr_reg     <= x"12345678";
        src_sel      <= 0;          -- Reg
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';
        wait for 1 ns;
        check_addr("TC-33-pre-reset", x"12345678");
        do_reset;
        src_sel      <= 0;
        addr_reg     <= x"12345678";  -- re-drive; reset may clear internal mux state
        wait for 1 ns;
        check_addr("TC-33-post-reset", x"12345678");

        -- =====================================================================
        -- TC-34: VBR addressing with displacement is zero after reset
        -- Mirrors TC-20 but executed immediately after a fresh reset, ensuring
        -- the displacement path through the shifter also produces H'00000000
        -- (VBR + 0 = H'00000000).
        -- =====================================================================
        report "---" severity note;
        report "TC-34: VBR + zero displacement after reset = H'00000000" severity note;
        do_reset;
        src_sel      <= 2;          -- VBR
        shift_sel    <= 2;          -- x4 (longword); 0 * 4 = 0
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';
        wait for 1 ns;
        check_addr("TC-34", x"00000000");

        -- =====================================================================
        -- TC-18 / TC-19: Load GBR and VBR (after reset tests, so internal
        -- state is clean).  These values are relied upon by TC-12 through TC-15
        -- and TC-20.
        -- SH-2 instructions: LDC Rm,GBR / LDC Rm,VBR
        -- =====================================================================

        -- TC-18: Load GBR = 0xFFFF_0000
        -- Corresponds to: LDC Rn,GBR  (Rn = 0xFFFF0000)
        report "TC-18: Load internal GBR register" severity note;
        load_GBR(x"FFFF0000");
        report "TC-18 [INFO] GBR loaded with 0xFFFF0000 (verify no address_out side-effect)" severity note;
        -- No address should be generated during a pure GBR load
        -- (address_out behaviour during load is implementation-defined;
        --  at minimum we check it doesn't become X)
        if address_out = (address_out'range => 'X') then
            report "TC-18 [FAIL] address_out is X during GBR load" severity error;
            test_counters.increment_fail;
        else
            report "TC-18 [PASS] address_out not X during GBR load" severity note;
            test_counters.increment_pass;
        end if;

        -- TC-19: Load VBR = 0xA000_0000
        -- Corresponds to: LDC Rn,VBR  (Rn = 0xA0000000)
        report "TC-19: Load internal VBR register" severity note;
        load_VBR(x"A0000000");
        report "TC-19 [INFO] VBR loaded with 0xA0000000" severity note;
        if address_out = (address_out'range => 'X') then
            report "TC-19 [FAIL] address_out is X during VBR load" severity error;
            test_counters.increment_fail;
        else
            report "TC-19 [PASS] address_out not X during VBR load" severity note;
            test_counters.increment_pass;
        end if;

        -- =====================================================================
        -- TC-01: Indirect register addressing  @Rn
        -- SH-2 instruction: MOV.L @Rn, Rm  (no offset, no inc/dec)
        -- address_out = addr_reg = 0x1000_0000
        -- addr_src_out not consumed (post mode, step irrelevant here but
        --   we set inc_dec_bit=0 / inc_dec_sel=0 as neutral)
        -- =====================================================================
        report "---" severity note;
        report "TC-01: Indirect register @Rn" severity note;
        addr_reg     <= x"10000000";
        src_sel      <= 0;          -- Reg
        shift_sel    <= 0;          -- x1
        offset_ins   <= x"00000000";
        offset_sel   <= 0;          -- instruction offset
        inc_dec_sel  <= '0';        -- increment (neutral)
        inc_dec_bit  <= 0;          -- step 1
        pre_post_sel <= '0';        -- pre (addr = original base)
        wait for 1 ns;
        -- address_out should equal addr_reg (zero offset)
        check_addr("TC-01", x"10000000");

        -- =====================================================================
        -- TC-02: Post-increment (byte)  @Rn+
        -- SH-2: MOV.B @Rn+, Rm
        -- address_out = Rn = 0x2000_0000 (access BEFORE increment)
        -- addr_src_out = Rn + 1 = 0x2000_0001
        -- =====================================================================
        report "---" severity note;
        report "TC-02: Post-increment byte @Rn+" severity note;
        addr_reg     <= x"20000000";
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';        -- increment
        inc_dec_bit  <= 0;          -- step = 2^0 = 1 (byte)
        pre_post_sel <= '0';        
        wait for 1 ns;
        check_addr("TC-02a", x"20000000");
        check_src ("TC-02b", x"20000001");

        -- =====================================================================
        -- TC-03: Post-increment (word)  @Rn+
        -- SH-2: MOV.W @Rn+, Rm
        -- address_out = Rn = 0x2000_0010
        -- addr_src_out = Rn + 2 = 0x2000_0012
        -- =====================================================================
        report "---" severity note;
        report "TC-03: Post-increment word @Rn+" severity note;
        addr_reg     <= x"20000010";
        inc_dec_bit  <= 1;          -- step = 2^1 = 2 (word)
        wait for 1 ns;
        check_addr("TC-03a", x"20000010");
        check_src ("TC-03b", x"20000012");

        -- =====================================================================
        -- TC-04: Post-increment (longword)  @Rn+
        -- SH-2: MOV.L @Rn+, Rm
        -- address_out = Rn = 0x2000_0020
        -- addr_src_out = Rn + 4 = 0x2000_0024
        -- =====================================================================
        report "---" severity note;
        report "TC-04: Post-increment longword @Rn+" severity note;
        addr_reg     <= x"20000020";
        inc_dec_bit  <= 2;          -- step = 2^2 = 4 (longword)
        wait for 1 ns;
        check_addr("TC-04a", x"20000020");
        check_src ("TC-04b", x"20000024");

        -- =====================================================================
        -- TC-05: Pre-decrement (byte)  @-Rn
        -- SH-2: MOV.B Rm, @-Rn
        -- address_out = Rn - 1 = 0x3000_00FF (access AFTER decrement)
        -- addr_src_out = Rn - 1 = 0x3000_00FF
        -- =====================================================================
        report "---" severity note;
        report "TC-05: Pre-decrement byte @-Rn" severity note;
        addr_reg     <= x"30000100";
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '1';        -- decrement
        inc_dec_bit  <= 0;          -- step = 1
        pre_post_sel <= '1';        
        wait for 1 ns;
        check_addr("TC-05a", x"300000FF");
        check_src ("TC-05b", x"300000FF");

        -- =====================================================================
        -- TC-06: Pre-decrement (word)  @-Rn
        -- SH-2: MOV.W Rm, @-Rn
        -- Rn = 0x3000_0100
        -- address_out = Rn - 2 = 0x3000_00FE
        -- addr_src_out = 0x3000_00FE
        -- =====================================================================
        report "---" severity note;
        report "TC-06: Pre-decrement word @-Rn" severity note;
        addr_reg     <= x"30000100";
        inc_dec_bit  <= 1;          -- step = 2
        pre_post_sel <= '1';        
        inc_dec_sel  <= '1';
        wait for 1 ns;
        check_addr("TC-06a", x"300000FE");
        check_src ("TC-06b", x"300000FE");

        -- =====================================================================
        -- TC-07: Pre-decrement (longword)  @-Rn
        -- SH-2: MOV.L Rm, @-Rn
        -- Rn = 0x3000_0100
        -- address_out = Rn - 4 = 0x3000_00FC
        -- addr_src_out = 0x3000_00FC
        -- =====================================================================
        report "---" severity note;
        report "TC-07: Pre-decrement longword @-Rn" severity note;
        addr_reg     <= x"30000100";
        inc_dec_bit  <= 2;          -- step = 4
        wait for 1 ns;
        check_addr("TC-07a", x"300000FC");
        check_src ("TC-07b", x"300000FC");

        -- =====================================================================
        -- TC-08: Indirect register + displacement (byte)  @(disp,Rn)
        -- SH-2: MOV.B @(disp,Rm), R0  -- disp=5, shift x1
        -- Rn = 0x1000_0000, disp = 5
        -- address_out = 0x1000_0000 + 5 = 0x1000_0005
        -- =====================================================================
        report "---" severity note;
        report "TC-08: @(disp,Rn) byte displacement x1" severity note;
        addr_reg     <= x"10000000";
        src_sel      <= 0;
        shift_sel    <= 0;          -- x1
        offset_ins   <= x"00000005";
        offset_sel   <= 0;          -- instruction offset
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';        
        wait for 1 ns;
        check_addr("TC-08", x"10000005");

        -- =====================================================================
        -- TC-09: Indirect register + displacement (word)  @(disp,Rn)
        -- SH-2: MOV.W @(disp,Rm), R0  -- disp=3, shift x2
        -- Rn = 0x1000_0000, disp = 3 => effective offset = 3*2 = 6
        -- address_out = 0x1000_0006
        -- =====================================================================
        report "---" severity note;
        report "TC-09: @(disp,Rn) word displacement x2" severity note;
        addr_reg     <= x"10000000";
        shift_sel    <= 1;          -- x2
        offset_ins   <= x"00000003";
        wait for 1 ns;
        check_addr("TC-09", x"10000006");

        -- =====================================================================
        -- TC-10: Indirect register + displacement (longword)  @(disp,Rn)
        -- SH-2: MOV.L @(disp,Rm), Rn  -- disp=2, shift x4
        -- Rn = 0x1000_0000, disp = 2 => effective offset = 2*4 = 8
        -- address_out = 0x1000_0008
        -- =====================================================================
        report "---" severity note;
        report "TC-10: @(disp,Rn) longword displacement x4" severity note;
        addr_reg     <= x"10000000";
        shift_sel    <= 2;          -- x4
        offset_ins   <= x"00000002";
        wait for 1 ns;
        check_addr("TC-10", x"10000008");

        -- =====================================================================
        -- TC-11: Indirect indexed register  @(R0,Rn)
        -- SH-2: MOV.L @(R0,Rn), Rm
        -- Rn = 0x1000_0000, R0 = 0x0000_0010  (passed as offset_reg)
        -- address_out = 0x1000_0010
        -- =====================================================================
        report "---" severity note;
        report "TC-11: @(R0,Rn) indirect indexed" severity note;
        addr_reg     <= x"10000000";
        src_sel      <= 0;
        shift_sel    <= 0;          -- R0 passed directly, no shift applied
        offset_ins   <= x"00000000";
        offset_reg   <= x"00000010";  -- R0
        offset_sel   <= 1;            -- use offset_reg (R0)
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';       
        wait for 1 ns;
        check_addr("TC-11", x"10000010");

        -- =====================================================================
        -- TC-12: Indirect GBR + displacement (byte)  @(disp,GBR)
        -- SH-2: MOV.B @(disp,GBR), R0  -- disp=12
        -- GBR was loaded as 0xFFFF_0000 (TC-18)
        -- address_out = 0xFFFF_0000 + 12 = 0xFFFF_000C
        -- =====================================================================
        report "---" severity note;
        report "TC-12: @(disp,GBR) byte x1" severity note;
        -- GBR is internal (loaded in TC-18 = 0xFFFF0000)
        src_sel      <= 1;          -- GBR
        shift_sel    <= 0;          -- x1
        offset_ins   <= x"0000000C";  -- disp=12
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';       
        wait for 1 ns;
        check_addr("TC-12", x"FFFF000C");

        -- =====================================================================
        -- TC-13: Indirect GBR + displacement (word)  @(disp,GBR)
        -- SH-2: MOV.W @(disp,GBR), R0  -- disp=6, x2 => offset=12
        -- GBR = 0xFFFF_0000
        -- address_out = 0xFFFF_0000 + 12 = 0xFFFF_000C
        -- =====================================================================
        report "---" severity note;
        report "TC-13: @(disp,GBR) word x2" severity note;
        src_sel      <= 1;
        shift_sel    <= 1;          -- x2
        offset_ins   <= x"00000006";  -- disp=6
        wait for 1 ns;
        check_addr("TC-13", x"FFFF000C");

        -- =====================================================================
        -- TC-14: Indirect GBR + displacement (longword)  @(disp,GBR)
        -- SH-2: MOV.L @(disp,GBR), R0  -- disp=3, x4 => offset=12
        -- GBR = 0xFFFF_0000
        -- address_out = 0xFFFF_000C
        -- =====================================================================
        report "---" severity note;
        report "TC-14: @(disp,GBR) longword x4" severity note;
        src_sel      <= 1;
        shift_sel    <= 2;          -- x4
        offset_ins   <= x"00000003";  -- disp=3
        wait for 1 ns;
        check_addr("TC-14", x"FFFF000C");

        -- =====================================================================
        -- TC-15: Indirect indexed GBR  @(R0,GBR)
        -- SH-2: AND.B #imm, @(R0,GBR)
        -- GBR = 0xFFFF_0000, R0 = 0x0000_0004
        -- address_out = 0xFFFF_0004
        -- =====================================================================
        report "---" severity note;
        report "TC-15: @(R0,GBR) indexed GBR" severity note;
        src_sel      <= 1;          -- GBR
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_reg   <= x"00000004";  -- R0 = 4
        offset_sel   <= 1;            -- use R0
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';        
        wait for 1 ns;
        check_addr("TC-15", x"FFFF0004");

        -- =====================================================================
        -- TC-16: PC-relative displacement (word)  @(disp,PC) x2
        -- SH-2: MOV.W @(disp,PC), Rn  -- disp=8 => offset = 8*2 = 16
        -- PC = 0x0000_1000 (addr_PC), word: address = PC + disp*2
        -- address_out = 0x0000_1010
        -- =====================================================================
        report "---" severity note;
        report "TC-16: @(disp,PC) word x2 PC-relative" severity note;
        addr_PC      <= x"00001000";
        src_sel      <= 3;          -- PC  [requires BUG-001 fix]
        shift_sel    <= 1;          -- x2
        offset_ins   <= x"00000008";  -- disp=8
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';        
        wait for 1 ns;
        check_addr("TC-16", x"00001010");

        -- =====================================================================
        -- TC-17: PC-relative displacement (longword)  @(disp,PC) x4
        -- SH-2: MOV.L @(disp,PC), Rn  -- disp=4 => offset = 4*4 = 16
        -- The SH-2 masks the lowest 2 bits of PC for longword PC-relative:
        --   effective_PC = PC & 0xFFFFFFFC
        -- PC = 0x0000_1002 => effective_PC = 0x0000_1000
        -- address_out = 0x0000_1000 + 16 = 0x0000_1010
        -- =====================================================================
        report "---" severity note;
        report "TC-17: @(disp,PC) longword x4 with PC[1:0] mask" severity note;
        addr_PC      <= x"00001002";  -- deliberately un-aligned
        src_sel      <= 3;            -- PC
        shift_sel    <= 2;            -- x4 => also triggers PC masking
        offset_ins   <= x"00000004";  -- disp=4
        wait for 1 ns;
        check_addr("TC-17", x"00001010");  -- based on PC & FFFC = 0x1000

        -- =====================================================================
        -- TC-20: src_sel=2 VBR indirect
        -- VBR was loaded as 0xA000_0000 in TC-19
        -- SH-2: indirect VBR used by exception processing
        -- address_out = VBR + 0 = 0xA000_0000
        -- =====================================================================
        report "---" severity note;
        report "TC-20: VBR indirect (src_sel=2)" severity note;
        src_sel      <= 2;          -- VBR
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';      
        wait for 1 ns;
        check_addr("TC-20", x"A0000000");

        -- =====================================================================
        -- TC-21: Offset from R0 (offset_reg) with shift x2
        -- SH-2: MOV.W @(R0,Rn) where R0 is shifted — not standard SH-2 but
        --       validates shift_sel applies to offset_reg path.
        -- Rn = 0x2000_0000, R0 = 0x0000_0004, shift x2 => offset = 8
        -- address_out = 0x2000_0008
        -- NOTE: This addressing mode is not part of the standard SH-2 instruction set
        -- so it has been removed, SH-2 does not require shifting to be applied to the offset_reg path. 
        -- =====================================================================
        report "---" severity note;
        report "TC-21: offset_reg with shift x2 REMOVED" severity note;
        -- addr_reg     <= x"20000000";
        -- src_sel      <= 0;
        -- shift_sel    <= 1;          -- x2
        -- offset_ins   <= x"00000000";
        -- offset_reg   <= x"00000004";
        -- offset_sel   <= 1;          -- use R0
        -- inc_dec_sel  <= '0';
        -- inc_dec_bit  <= 0;
        -- pre_post_sel <= '0';        -- MAU PRE: address = original Rn + R0*shift
        -- wait for 1 ns;
        -- check_addr("TC-21", x"20000008");

        -- =====================================================================
        -- TC-22: Zero displacement
        -- address_out = addr_reg = 0x5000_0000
        -- =====================================================================
        report "---" severity note;
        report "TC-22: Zero displacement" severity note;
        addr_reg     <= x"50000000";
        src_sel      <= 0;
        shift_sel    <= 2;          -- x4 but offset=0 so result unchanged
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';        
        wait for 1 ns;
        check_addr("TC-22", x"50000000");

        -- =====================================================================
        -- TC-23: Maximum 8-bit displacement with GBR
        -- SH-2 GBR byte: disp_max = 0xFF => address = GBR + 255
        --        GBR word: disp_max = 0xFF => address = GBR + 510
        --        GBR lword:disp_max = 0xFF => address = GBR + 1020
        -- GBR = 0xFFFF_0000
        -- =====================================================================
        report "---" severity note;
        report "TC-23a: Max GBR byte disp (0xFF x1)" severity note;
        src_sel      <= 1;
        shift_sel    <= 0;
        offset_ins   <= x"000000FF";
        offset_sel   <= 0;
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';        
        wait for 1 ns;
        check_addr("TC-23a", x"FFFF00FF");  -- GBR + 255

        report "TC-23b: Max GBR word disp (0xFF x2 = 510 = 0x1FE)" severity note;
        shift_sel    <= 1;
        offset_ins   <= x"000000FF";
        wait for 1 ns;
        check_addr("TC-23b", x"FFFF01FE");  -- GBR + 510

        report "TC-23c: Max GBR lword disp (0xFF x4 = 1020 = 0x3FC)" severity note;
        shift_sel    <= 2;
        offset_ins   <= x"000000FF";
        wait for 1 ns;
        check_addr("TC-23c", x"FFFF03FC");  -- GBR + 1020

        -- =====================================================================
        -- TC-24: Maximum 4-bit displacement with Rn
        -- SH-2 @(disp,Rn): byte disp_max=15, word max=30, lword max=60
        -- Rn = 0x0000_0000
        -- =====================================================================
        report "---" severity note;
        report "TC-24a: Max Rn byte disp (15 x1)" severity note;
        addr_reg     <= x"00000000";
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= x"0000000F";  -- 4-bit max = 15
        offset_sel   <= 0;
        wait for 1 ns;
        check_addr("TC-24a", x"0000000F");

        report "TC-24b: Max Rn word disp (15 x2 = 30 = 0x1E)" severity note;
        shift_sel    <= 1;
        wait for 1 ns;
        check_addr("TC-24b", x"0000001E");

        report "TC-24c: Max Rn lword disp (15 x4 = 60 = 0x3C)" severity note;
        shift_sel    <= 2;
        wait for 1 ns;
        check_addr("TC-24c", x"0000003C");

        -- =====================================================================
        -- TC-25: 32-bit address wrap-around
        -- Post-increment with Rn = 0xFFFF_FFFF, step = 1 (byte)
        -- address_out  = 0xFFFF_FFFF
        -- addr_src_out = 0x0000_0000  (wrap)
        -- =====================================================================
        report "---" severity note;
        report "TC-25: 32-bit wrap-around on post-increment" severity note;
        addr_reg     <= x"FFFFFFFF";
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';        -- increment
        inc_dec_bit  <= 0;          -- step 1
        pre_post_sel <= '0';        
        wait for 1 ns;
        check_addr("TC-25a", x"FFFFFFFF");
        check_src ("TC-25b", x"00000000");

        -- =====================================================================
        -- TC-26: Pre-decrement wrap-around
        -- Rn = 0x0000_0000, step = 4 (longword)
        -- address_out  = 0xFFFF_FFFC
        -- addr_src_out = 0xFFFF_FFFC
        -- =====================================================================
        report "---" severity note;
        report "TC-26: Wrap-around on pre-decrement (underflow)" severity note;
        addr_reg     <= x"00000000";
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '1';        -- decrement
        inc_dec_bit  <= 2;          -- step 4
        pre_post_sel <= '1';        -- MAU POST: address = Rn - step (decrement before access)
        wait for 1 ns;
        check_addr("TC-26a", x"FFFFFFFC");
        check_src ("TC-26b", x"FFFFFFFC");

        -- =====================================================================
        -- TC-27: Post-increment, indexed R0 offset + base
        -- Demonstrates offset_reg path combined with post-increment
        -- Rn = 0x3000_0000, R0 = 0x10, post-increment byte
        -- address_out  = 0x3000_0000 + 0x10 = 0x3000_0010
        -- addr_src_out = Rn + 1 = 0x3000_0001
        -- =====================================================================
        report "---" severity note;
        report "TC-27: Post-increment + R0 offset" severity note;
        addr_reg     <= x"30000000";
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_reg   <= x"00000010";
        offset_sel   <= 1;          -- R0 offset
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;          -- step 1
        pre_post_sel <= '0';        -- MAU PRE: address = original Rn + R0; AddrSrcOut = Rn + 1
        wait for 1 ns;
        check_addr("TC-27a", x"30000010");
        check_src ("TC-27b", x"30000001");

        -- =====================================================================
        -- TC-28: PC-relative (src_sel=3), longword with masking
        -- Already covered in TC-17; this verifies the same path with a
        -- different address to confirm consistent masking.
        -- PC = 0x0000_2006 => masked PC = 0x0000_2004
        -- disp=1, x4 => offset=4
        -- address_out = 0x0000_2008
        -- [requires BUG-001 fix: src_sel range 3 downto 0]
        -- =====================================================================
        report "---" severity note;
        report "TC-28: PC-relative longword mask, PC=0x2006 [BUG-001 required]" severity note;
        addr_PC      <= x"00002006";
        src_sel      <= 3;
        shift_sel    <= 2;
        offset_ins   <= x"00000001";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';        -- MAU PRE: address = original PC + disp
        wait for 1 ns;
        check_addr("TC-28", x"00002008");

        -- =====================================================================
        -- TC-29: Consecutive post-increments (simulating MOV.L @Rm+,Rn loop)
        -- Each tick the testbench feeds back addr_src_out => addr_reg
        -- Start Rn = 0x4000_0000, 3 iterations, step = 4 (longword)
        -- Iter 1: addr=0x4000_0000, src_out=0x4000_0004
        -- Iter 2: addr=0x4000_0004, src_out=0x4000_0008
        -- Iter 3: addr=0x4000_0008, src_out=0x4000_000C
        -- =====================================================================
        report "---" severity note;
        report "TC-29: Consecutive post-increments (3x longword)" severity note;
        addr_reg     <= x"40000000";
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 2;          -- step 4
        pre_post_sel <= '0';        -- MAU PRE: address = original Rn; AddrSrcOut = Rn + 4
        wait for 1 ns;
        check_addr("TC-29-iter1-addr", x"40000000");
        check_src ("TC-29-iter1-src",  x"40000004");
        -- Simulate writeback: feed addr_src_out back as the new Rn
        addr_reg <= addr_src_out;
        wait for 1 ns;
        check_addr("TC-29-iter2-addr", x"40000004");
        check_src ("TC-29-iter2-src",  x"40000008");
        addr_reg <= addr_src_out;
        wait for 1 ns;
        check_addr("TC-29-iter3-addr", x"40000008");
        check_src ("TC-29-iter3-src",  x"4000000C");

        -- =====================================================================
        -- TC-30: Consecutive pre-decrements (simulating MOV.L Rm,@-Rn loop)
        -- Start Rn = 0x5000_000C, 3 iterations, step = 4 (longword)
        -- Iter 1: src_out=addr=0x5000_0008
        -- Iter 2: src_out=addr=0x5000_0004
        -- Iter 3: src_out=addr=0x5000_0000
        -- =====================================================================
        report "---" severity note;
        report "TC-30: Consecutive pre-decrements (3x longword)" severity note;
        addr_reg     <= x"5000000C";
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '1';        -- decrement
        inc_dec_bit  <= 2;          -- step 4
        pre_post_sel <= '1';        -- MAU POST: address = Rn - step (decrement before access)
        wait for 1 ns;
        check_addr("TC-30-iter1-addr", x"50000008");
        check_src ("TC-30-iter1-src",  x"50000008");
        addr_reg <= addr_src_out;
        wait for 1 ns;
        check_addr("TC-30-iter2-addr", x"50000004");
        check_src ("TC-30-iter2-src",  x"50000004");
        addr_reg <= addr_src_out;
        wait for 1 ns;
        check_addr("TC-30-iter3-addr", x"50000000");
        check_src ("TC-30-iter3-src",  x"50000000");

        -- =====================================================================
        -- TC-35: PC masking edge cases for longword PC-relative access
        -- src_sel=3 (PC) + shift_sel=2 forces PC[1:0]=00 before adding offset
        -- TC-35a: PC=0xFFFFFFFE -> masked 0xFFFFFFFC + 4 = 0x00000000 (wrap)
        -- TC-35b: PC=0x00000003 -> masked 0x00000000 + 4 = 0x00000004
        -- TC-35c: PC=0xFFFFFFFC -> masked 0xFFFFFFFC + 0 = 0xFFFFFFFC (no offset)
        -- =====================================================================
        report "---" severity note;
        report "TC-35: PC[1:0] masking edge cases (shift_sel=2)" severity note;
        src_sel      <= 3;
        shift_sel    <= 2;
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';

        addr_PC    <= x"FFFFFFFE";
        offset_ins <= x"00000001";  -- disp=1, x4 = 4
        wait for 1 ns;
        check_addr("TC-35a", x"00000000");  -- (0xFFFFFFFC + 4) wraps

        addr_PC    <= x"00000003";
        offset_ins <= x"00000001";  -- disp=1, x4 = 4
        wait for 1 ns;
        check_addr("TC-35b", x"00000004");  -- (0x00000000 + 4)

        addr_PC    <= x"FFFFFFFC";
        offset_ins <= x"00000000";  -- no offset
        wait for 1 ns;
        check_addr("TC-35c", x"FFFFFFFC");  -- masked PC with zero offset

        -- =====================================================================
        -- TC-36: Negative (all-ones) displacement with each shift scale
        -- offset_ins=0xFFFFFFFF acts as -1; shifts produce -1, -2, -4
        -- =====================================================================
        report "---" severity note;
        report "TC-36: Negative all-ones offset with x1, x2, x4" severity note;
        addr_reg     <= x"10000000";
        src_sel      <= 0;
        offset_ins   <= x"FFFFFFFF";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';

        shift_sel <= 0;             -- 0xFFFFFFFF x1 = 0xFFFFFFFF -> +(-1)
        wait for 1 ns;
        check_addr("TC-36a", x"0FFFFFFF");  -- 0x10000000 - 1

        shift_sel <= 1;             -- 0xFFFFFFFF x2 = 0xFFFFFFFE -> +(-2)
        wait for 1 ns;
        check_addr("TC-36b", x"0FFFFFFE");  -- 0x10000000 - 2

        shift_sel <= 2;             -- 0xFFFFFFFF x4 = 0xFFFFFFFC -> +(-4)
        wait for 1 ns;
        check_addr("TC-36c", x"0FFFFFFC");  -- 0x10000000 - 4

        -- =====================================================================
        -- TC-37: VBR as interrupt vector base (reload VBR=0xA0000000 first)
        -- Models SH-2 exception vector table: VBR + vector_offset*4
        -- =====================================================================
        report "---" severity note;
        report "TC-37: VBR interrupt vector base access" severity note;
        addr_reg  <= x"A0000000";
        vbr_write <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        vbr_write <= '0';

        src_sel      <= 2;          -- VBR
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';

        shift_sel  <= 2;            -- x4
        offset_ins <= x"00000020";  -- disp=0x20, x4 = 0x80 (TRAPA #32)
        wait for 1 ns;
        check_addr("TC-37a", x"A0000080");

        offset_ins <= x"00000000";  -- zero vector offset -> VBR base
        wait for 1 ns;
        check_addr("TC-37b", x"A0000000");

        offset_ins <= x"000000FF";  -- max 8-bit disp x4 = 0x3FC
        wait for 1 ns;
        check_addr("TC-37c", x"A00003FC");

        shift_sel  <= 1;            -- x2
        offset_ins <= x"00000040";  -- disp=0x40, x2 = 0x80
        wait for 1 ns;
        check_addr("TC-37d", x"A0000080");  -- same address, different path

        -- =====================================================================
        -- TC-38: Post-increment word step wrapping across 0xFFFFFFFF
        -- Rn=0xFFFFFFFE, step=2: address=0xFFFFFFFE, src_out=0x00000000
        -- =====================================================================
        report "---" severity note;
        report "TC-38: Post-increment word step wrapping at 0xFFFFFFFE" severity note;
        addr_reg     <= x"FFFFFFFE";
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 1;          -- step=2^1=2 (word)
        pre_post_sel <= '0';        
        wait for 1 ns;
        check_addr("TC-38a", x"FFFFFFFE");
        check_src ("TC-38b", x"00000000");  -- FE+2 wraps to 0

        -- =====================================================================
        -- TC-39: Pre-decrement crossing the 0x80000000 signed boundary
        -- Rn=0x80000000 - 4 = 0x7FFFFFFC
        -- =====================================================================
        report "---" severity note;
        report "TC-39: Pre-decrement across 0x80000000 sign boundary" severity note;
        addr_reg     <= x"80000000";
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '1';        -- decrement
        inc_dec_bit  <= 2;          -- step=2^2=4
        pre_post_sel <= '1';      
        wait for 1 ns;
        check_addr("TC-39a", x"7FFFFFFC");
        check_src ("TC-39b", x"7FFFFFFC");

        -- =====================================================================
        -- TC-40: @(R0,GBR) with R0+GBR = 0xFFFFFFFF (max address, GBR=0xFFFF0000)
        -- =====================================================================
        report "---" severity note;
        report "TC-40: @(R0,GBR) producing max address 0xFFFFFFFF" severity note;
        src_sel      <= 1;          -- GBR (= 0xFFFF0000 from TC-18)
        shift_sel    <= 0;
        offset_reg   <= x"0000FFFF";
        offset_sel   <= 1;          -- R0
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';
        wait for 1 ns;
        check_addr("TC-40", x"FFFFFFFF");

        -- =====================================================================
        -- TC-41: Consecutive GBR then VBR loads in adjacent clock cycles
        -- Verifies the two internal registers are independent
        -- =====================================================================
        report "---" severity note;
        report "TC-41: Consecutive GBR=0x12340000 then VBR=0xABCD0000 loads" severity note;
        addr_reg  <= x"12340000";
        gbr_write <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        gbr_write <= '0';

        addr_reg  <= x"ABCD0000";
        vbr_write <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        vbr_write <= '0';

        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';

        src_sel <= 1;               -- GBR
        wait for 1 ns;
        check_addr("TC-41a-GBR", x"12340000");

        src_sel <= 2;               -- VBR
        wait for 1 ns;
        check_addr("TC-41b-VBR", x"ABCD0000");

        -- =====================================================================
        -- TC-42: Pre-decrement byte step from 0x00000000 underflows to 0xFFFFFFFF
        -- =====================================================================
        report "---" severity note;
        report "TC-42: Pre-decrement byte from 0 underflows to 0xFFFFFFFF" severity note;
        addr_reg     <= x"00000000";
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '1';        -- decrement
        inc_dec_bit  <= 0;          -- step=1 (byte)
        pre_post_sel <= '1';      
        wait for 1 ns;
        check_addr("TC-42a", x"FFFFFFFF");
        check_src ("TC-42b", x"FFFFFFFF");

        -- =====================================================================
        -- TC-43: Post-increment byte step from 0xFFFFFFFF overflows src_out to 0
        -- =====================================================================
        report "---" severity note;
        report "TC-43: Post-increment byte from 0xFFFFFFFF overflows src_out to 0" severity note;
        addr_reg     <= x"FFFFFFFF";
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';        -- increment
        inc_dec_bit  <= 0;          -- step=1
        pre_post_sel <= '0';        
        wait for 1 ns;
        check_addr("TC-43a", x"FFFFFFFF");
        check_src ("TC-43b", x"00000000");

        -- =====================================================================
        -- TC-44: Zero base register with all three shift scales
        -- =====================================================================
        report "---" severity note;
        report "TC-44: @(disp,Rn) with Rn=0 and each shift scale" severity note;
        addr_reg     <= x"00000000";
        src_sel      <= 0;
        offset_ins   <= x"00000010";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';

        shift_sel <= 0;             -- 0x10 x1 = 0x10
        wait for 1 ns;
        check_addr("TC-44a", x"00000010");

        shift_sel <= 1;             -- 0x10 x2 = 0x20
        wait for 1 ns;
        check_addr("TC-44b", x"00000020");

        shift_sel <= 2;             -- 0x10 x4 = 0x40
        wait for 1 ns;
        check_addr("TC-44c", x"00000040");

        -- =====================================================================
        -- TC-45: All src_sel zero-offset passthroughs (GBR/VBR from TC-41)
        -- =====================================================================
        report "---" severity note;
        report "TC-45: All src_sel passthroughs with zero offset" severity note;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '0';
        inc_dec_bit  <= 0;
        pre_post_sel <= '0';

        addr_reg <= x"CAFEBABE";
        src_sel  <= 0;
        wait for 1 ns;
        check_addr("TC-45a-Rn",  x"CAFEBABE");

        src_sel  <= 1;              -- GBR = 0x12340000 (loaded in TC-41)
        wait for 1 ns;
        check_addr("TC-45b-GBR", x"12340000");

        src_sel  <= 2;              -- VBR = 0xABCD0000 (loaded in TC-41)
        wait for 1 ns;
        check_addr("TC-45c-VBR", x"ABCD0000");

        -- =====================================================================
        -- TC-46: GBR-relative indexed with zero R0 (isolates GBR passthrough)
        -- =====================================================================
        report "---" severity note;
        report "TC-46: @(R0=0,GBR) - R0=0 so address = GBR exactly" severity note;
        src_sel    <= 1;            -- GBR = 0x12340000
        shift_sel  <= 0;
        offset_reg <= x"00000000";
        offset_sel <= 1;            -- R0
        wait for 1 ns;
        check_addr("TC-46", x"12340000");

        -- =====================================================================
        -- TC-47: Pre-decrement word step then post-increment word step cancel
        -- Two operations on the same base, verify addr_src_out values
        -- Rn=0x20000010, dec step=2 -> src=0x2000000E, then inc step=2 -> src=0x20000010
        -- =====================================================================
        report "---" severity note;
        report "TC-47: Pre-dec then post-inc by word step, cancels back to original" severity note;
        addr_reg     <= x"20000010";
        src_sel      <= 0;
        shift_sel    <= 0;
        offset_ins   <= x"00000000";
        offset_sel   <= 0;
        inc_dec_sel  <= '1';        -- decrement
        inc_dec_bit  <= 1;          -- step=2
        pre_post_sel <= '1';       
        wait for 1 ns;
        check_addr("TC-47a-dec-addr", x"2000000E");
        check_src ("TC-47b-dec-src",  x"2000000E");

        -- now post-increment from 0x2000000E by step=2 -> address=0x2000000E, src=0x20000010
        addr_reg     <= x"2000000E";
        inc_dec_sel  <= '0';        -- increment
        pre_post_sel <= '0';        
        wait for 1 ns;
        check_addr("TC-47c-inc-addr", x"2000000E");
        check_src ("TC-47d-inc-src",  x"20000010");

        -- =====================================================================
        -- Final summary
        -- =====================================================================
        report "========================================" severity note;
        report "TEST SUMMARY" severity note;
        report "  PASS: " & integer'image(test_counters.get_pass) severity note;
        report "  FAIL: " & integer'image(test_counters.get_fail) severity note;
        report "========================================" severity note;

        if test_counters.get_fail = 0 then
            report "ALL TESTS PASSED" severity note;
        else
            report integer'image(test_counters.get_fail) & " TEST(S) FAILED"
                severity failure;
        end if;

        wait;
    end process stim;

end architecture sim;