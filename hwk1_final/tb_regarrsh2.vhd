--------------------------------------------------------------------------------
-- Testbench: tb_RegArrSH2
--
-- Device Under Test: RegArrSH2
--
-- Purpose:
--   Comprehensive verification of the SH2 16x32-bit general-purpose register
--   array.  Tests cover:
--     * Basic single-register write and read-back on all four output ports
--     * All 16 registers independently writable and readable
--     * Main write port (reg_in / reg_in_sel / reg_store)
--     * Address write port (reg_ax_in / reg_ax_sel / reg_ax_store)
--     * Write-enable gating (store = '0' must NOT update the register)
--     * Simultaneous independent reads across all four output ports
--     * Simultaneous write on both write ports to DIFFERENT registers
--     * Write-port conflict: both ports target the SAME register on the
--       same rising edge (result must be deterministic -- see note below)
--     * R0 role as index register (address = Rn + R0 pattern)
--     * R15 role as hardware stack pointer
--     * Boundary data values: 0x00000000 and 0xFFFFFFFF
--     * Read-port independence: reading from one port never corrupts another
--     * Address port read-back (reg_a1 reflects reg_ax_sel after write)
--     * Register retention: unselected registers hold their values
--
-- Notes:
--   1. The double-width (64-bit) access feature is NOT exercised because the
--      SH2 instantiation does not require it; those inputs are driven to their
--      inactive/null states.
--   2. The write-conflict test (TC-14) writes via BOTH ports to the same
--      register in the same cycle.  Depending on the implementation, either
--      port may win.  The testbench checks only that SOME deterministic value
--      appears and prints a diagnostic.
--   3. Clock period is 10 ns (100 MHz).  All stimulus is applied on the
--      falling edge; checks are made after the following rising edge.
--
-- Fixes applied vs. first version:
--   * Removed all inline declare...begin...end blocks (illegal inside a
--     process in VHDL-93/2008); all local declarations moved to the process
--     declarative region.
--   * Array types used by TC-07 and TC-15 hoisted to the architecture
--     declarative region.
--   * Every separator line now carries a leading "--".
--   * tick() now takes the clock signal as a formal parameter.
--
-- Revision history:
--   8 Apr 26  Claude Code    Initial version
--   8 Apr 26  Claude Code    Corrected compilation errors
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_RegArrSH2 is
end entity tb_RegArrSH2;

architecture sim of tb_RegArrSH2 is

    ---------------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------------
    constant CLK_PERIOD : time    := 10 ns;
    constant NUM_REGS   : integer := 16;

    ---------------------------------------------------------------------------
    -- DUT port signals
    ---------------------------------------------------------------------------
    signal reg_in       : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_in_sel   : integer range 15 downto 0     := 0;
    signal reg_store    : std_logic                     := '0';
    signal reg_a_sel    : integer range 15 downto 0     := 0;
    signal reg_b_sel    : integer range 15 downto 0     := 0;
    signal reg_ax_in    : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_ax_sel   : integer range 15 downto 0     := 0;
    signal reg_ax_store : std_logic                     := '0';
    signal reg_a2_sel   : integer range 15 downto 0     := 0;
    signal clock        : std_logic                     := '0';
    signal reg_a        : std_logic_vector(31 downto 0);
    signal reg_b        : std_logic_vector(31 downto 0);
    signal reg_a1       : std_logic_vector(31 downto 0);
    signal reg_a2       : std_logic_vector(31 downto 0);

    ---------------------------------------------------------------------------
    -- Test progress tracking
    -- current_tc is a fixed-length string signal visible in any waveform
    -- viewer (GTKWave, etc.) and printed in the crash message.  Update it
    -- at the top of every test case so a simulation abort tells you exactly
    -- which TC was executing.  Length 40 covers "TC-XX: <short description>".
    ---------------------------------------------------------------------------
    subtype t_tc_name is string(1 to 40);
    signal current_tc : t_tc_name := (others => ' ');

    ---------------------------------------------------------------------------
    -- Test bookkeeping
    -- VHDL-2008 requires shared variables to be of a protected type.
    -- The protected type below wraps the two counters and exposes increment
    -- and read operations so the stimulus process and check procedure can
    -- update them safely.
    ---------------------------------------------------------------------------
    type t_scoreboard is protected
        procedure increment_pass;
        procedure increment_fail;
        impure function get_pass return integer;
        impure function get_fail return integer;
    end protected t_scoreboard;

    type t_scoreboard is protected body
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
    end protected body t_scoreboard;

    shared variable scoreboard : t_scoreboard;

    ---------------------------------------------------------------------------
    -- Array types used in TC-07 and TC-15
    -- (must be declared in the architecture region, not inside a process)
    ---------------------------------------------------------------------------
    type words4_t    is array(0 to 3) of std_logic_vector(31 downto 0);
    type integers4_t is array(0 to 3) of integer range 15 downto 0;

    ---------------------------------------------------------------------------
    -- Helper: advance past one rising clock edge with a small settling margin
    ---------------------------------------------------------------------------
    procedure tick(signal clk : in std_logic) is
    begin
        wait until rising_edge(clk);
        wait for 1 ns;
    end procedure;

    ---------------------------------------------------------------------------
    -- Helper: update current_tc and emit a report so the active test case is
    -- visible both in waveform dumps and in the GHDL console log.  The name
    -- is padded / truncated to the fixed subtype length so the signal stays
    -- well-formed throughout the simulation.
    ---------------------------------------------------------------------------
    procedure set_tc(signal tc_sig : out t_tc_name; name : in string) is
        variable v : t_tc_name := (others => ' ');
        variable len : integer;
    begin
        len := name'length;
        if len > t_tc_name'length then
            len := t_tc_name'length;
        end if;
        v(1 to len) := name(name'left to name'left + len - 1);
        tc_sig <= v;
        report ">>> " & name severity note;
    end procedure;

    ---------------------------------------------------------------------------
    -- Helper: assert expected == got, emit pass/fail report
    ---------------------------------------------------------------------------
    procedure check(
        tc_name  : in string;
        got      : in std_logic_vector(31 downto 0);
        expected : in std_logic_vector(31 downto 0)
    ) is
    begin
        if got = expected then
            report "PASS  [" & tc_name & "]"
                   & "  expected=0x" & to_hstring(expected)
                severity note;
            scoreboard.increment_pass;
        else
            report "FAIL  [" & tc_name & "]"
                   & "  expected=0x" & to_hstring(expected)
                   & "  got=0x"      & to_hstring(got)
                severity error;
            scoreboard.increment_fail;
        end if;
    end procedure;

    ---------------------------------------------------------------------------
    -- DUT component declaration
    ---------------------------------------------------------------------------
    component RegArrSH2 is
        port(
            reg_in       : in  std_logic_vector(31 downto 0);
            reg_in_sel   : in  integer range 15 downto 0;
            reg_store    : in  std_logic;
            reg_a_sel    : in  integer range 15 downto 0;
            reg_b_sel    : in  integer range 15 downto 0;
            reg_ax_in    : in  std_logic_vector(31 downto 0);
            reg_ax_sel   : in  integer range 15 downto 0;
            reg_ax_store : in  std_logic;
            reg_a2_sel   : in  integer range 15 downto 0;
            clock        : in  std_logic;
            reg_a        : out std_logic_vector(31 downto 0);
            reg_b        : out std_logic_vector(31 downto 0);
            reg_a1       : out std_logic_vector(31 downto 0);
            reg_a2       : out std_logic_vector(31 downto 0)
        );
    end component;

begin

    ---------------------------------------------------------------------------
    -- Clock generation
    ---------------------------------------------------------------------------
    clk_gen : process
    begin
        clock <= '0';
        wait for CLK_PERIOD / 2;
        clock <= '1';
        wait for CLK_PERIOD / 2;
    end process clk_gen;

    ---------------------------------------------------------------------------
    -- DUT instantiation
    ---------------------------------------------------------------------------
    dut : RegArrSH2
        port map(
            reg_in       => reg_in,
            reg_in_sel   => reg_in_sel,
            reg_store    => reg_store,
            reg_a_sel    => reg_a_sel,
            reg_b_sel    => reg_b_sel,
            reg_ax_in    => reg_ax_in,
            reg_ax_sel   => reg_ax_sel,
            reg_ax_store => reg_ax_store,
            reg_a2_sel   => reg_a2_sel,
            clock        => clock,
            reg_a        => reg_a,
            reg_b        => reg_b,
            reg_a1       => reg_a1,
            reg_a2       => reg_a2
        );

    ---------------------------------------------------------------------------
    -- Stimulus process
    -- All local declarations appear here, before the first "begin".
    ---------------------------------------------------------------------------
    stim : process

        -- General-purpose scratch
        variable data_v     : std_logic_vector(31 downto 0);
        variable walking1_v : std_logic_vector(31 downto 0);
        variable sum_v      : std_logic_vector(31 downto 0);
        variable eff_addr_v : unsigned(31 downto 0);

        -- TC-07: four registers loaded and read simultaneously
        constant TC07_VALUES : words4_t    := (x"11111111", x"22222222",
                                               x"33333333", x"44444444");
        constant TC07_REGS   : integers4_t := (2, 4, 6, 9);

        -- TC-15: four sentinel values for read-port independence test
        constant TC15_SENTINELS : words4_t    := (x"AABB0000", x"CCDD1111",
                                                  x"EEFF2222", x"00113333");
        constant TC15_REGS      : integers4_t := (1, 2, 11, 12);

    begin

        -- Allow the design to settle after power-on
        wait for CLK_PERIOD * 2;

        -- =====================================================================
        -- TC-01  Basic write + read-back via reg_a (main write port)
        --        Write a unique value to each of the 16 registers via the
        --        main write port and verify reg_a reflects the correct value.
        -- =====================================================================
        report "=== TC-01: Basic write/read, all 16 registers via main port ===" severity note;
        set_tc(current_tc, "TC-01: write/read main port");

        for i in 0 to NUM_REGS - 1 loop
            data_v := x"A5A5" & std_logic_vector(to_unsigned(i * 16#11#, 16));

            wait until falling_edge(clock);
            reg_in     <= data_v;
            reg_in_sel <= i;
            reg_store  <= '1';
            reg_a_sel  <= i;

            tick(clock);
            reg_store <= '0';

            check("TC-01 R" & integer'image(i) & " reg_a", reg_a, data_v);
        end loop;

        -- =====================================================================
        -- TC-02  Basic write + read-back via reg_b (ALU port B)
        --        Same pattern as TC-01 but verified on reg_b.
        -- =====================================================================
        report "=== TC-02: Read-back on reg_b port ===" severity note;
        set_tc(current_tc, "TC-02: read-back reg_b");

        for i in 0 to NUM_REGS - 1 loop
            data_v := x"B0B0" & std_logic_vector(to_unsigned(i * 16#11#, 16));

            wait until falling_edge(clock);
            reg_in     <= data_v;
            reg_in_sel <= i;
            reg_store  <= '1';
            reg_b_sel  <= i;

            tick(clock);
            reg_store <= '0';

            check("TC-02 R" & integer'image(i) & " reg_b", reg_b, data_v);
        end loop;

        -- =====================================================================
        -- TC-03  Write-enable gating -- main port
        --        Assert reg_store='0'; the register must NOT be updated.
        -- =====================================================================
        report "=== TC-03: Write-enable gating (main port, store='0') ===" severity note;
        set_tc(current_tc, "TC-03: store gate main port");

        -- Write a known sentinel value into R5
        wait until falling_edge(clock);
        reg_in     <= x"DEADBEEF";
        reg_in_sel <= 5;
        reg_store  <= '1';
        reg_a_sel  <= 5;
        tick(clock);
        reg_store <= '0';
        check("TC-03 sentinel", reg_a, x"DEADBEEF");

        -- Attempt overwrite with store disabled -- R5 must stay unchanged
        wait until falling_edge(clock);
        reg_in     <= x"CAFECAFE";
        reg_in_sel <= 5;
        reg_store  <= '0';
        tick(clock);
        check("TC-03 R5 unchanged", reg_a, x"DEADBEEF");

        -- =====================================================================
        -- TC-04  Write-enable gating -- address port
        --        Assert reg_ax_store='0'; the register must NOT be updated.
        -- =====================================================================
        report "=== TC-04: Write-enable gating (address port, ax_store='0') ===" severity note;
        set_tc(current_tc, "TC-04: store gate addr port");

        -- Write sentinel into R8 via address port
        wait until falling_edge(clock);
        reg_ax_in    <= x"12345678";
        reg_ax_sel   <= 8;
        reg_ax_store <= '1';
        reg_a_sel    <= 8;
        tick(clock);
        reg_ax_store <= '0';
        check("TC-04 sentinel", reg_a, x"12345678");

        -- Attempt overwrite with ax_store disabled -- R8 must stay unchanged
        wait until falling_edge(clock);
        reg_ax_in    <= x"AAAABBBB";
        reg_ax_sel   <= 8;
        reg_ax_store <= '0';
        tick(clock);
        check("TC-04 R8 unchanged", reg_a, x"12345678");

        -- =====================================================================
        -- TC-05  Address write port functional check
        --        reg_a1 is hardwired to read R0 in the SH2 wrapper
        --        (reg_a1_sel is permanently 0).  This TC therefore has two
        --        parts:
        --          (a) Verify that ax writes to ALL 16 registers actually land
        --              by reading back via reg_a (main ALU read port).
        --          (b) Verify that reg_a1 tracks R0's value regardless of
        --              which register reg_ax_sel points to.
        -- =====================================================================
        report "=== TC-05: Address port write + reg_a1 always-R0 check ==="
            severity note;
        set_tc(current_tc, "TC-05: addr port reg_a1");

        -- First write a known value into R0 so reg_a1 has a predictable value
        wait until falling_edge(clock);
        reg_ax_in    <= x"C0DE0000";
        reg_ax_sel   <= 0;
        reg_ax_store <= '1';
        tick(clock);
        reg_ax_store <= '0';

        -- (a) Write every register via ax port; read back each one via reg_a
        for i in 0 to NUM_REGS - 1 loop
            data_v := x"C0DE" & std_logic_vector(to_unsigned(i * 16#11#, 16));

            wait until falling_edge(clock);
            reg_ax_in    <= data_v;
            reg_ax_sel   <= i;
            reg_ax_store <= '1';
            reg_a_sel    <= i;
            tick(clock);
            reg_ax_store <= '0';

            check("TC-05a R" & integer'image(i) & " ax write via reg_a",
                  reg_a, data_v);
        end loop;

        -- (b) After the loop R0 now holds x"C0DE0000" (first write above).
        --     Step through several different reg_ax_sel values and confirm
        --     reg_a1 always outputs R0, never the selected register.
        for i in 1 to NUM_REGS - 1 loop
            wait until falling_edge(clock);
            reg_ax_sel <= i;    -- point ax read at a non-zero register
            tick(clock);
            check("TC-05b reg_a1 = R0 when reg_ax_sel=" & integer'image(i),
                  reg_a1, x"C0DE0000");
        end loop;

        -- =====================================================================
        -- TC-06  Address port read-back via reg_a2
        --        After writing a known value via the main port, confirm reg_a2
        --        returns the correct result when reg_a2_sel points to the same
        --        register.
        -- =====================================================================
        report "=== TC-06: reg_a2 port read-back ===" severity note;
        set_tc(current_tc, "TC-06: reg_a2 read-back");

        for i in 0 to NUM_REGS - 1 loop
            data_v := x"FACE" & std_logic_vector(to_unsigned(i * 16#11#, 16));

            wait until falling_edge(clock);
            reg_in     <= data_v;
            reg_in_sel <= i;
            reg_store  <= '1';
            reg_a2_sel <= i;
            tick(clock);
            reg_store <= '0';

            check("TC-06 R" & integer'image(i) & " reg_a2", reg_a2, data_v);
        end loop;

        -- =====================================================================
        -- TC-07  Simultaneous reads on all four output ports
        --        Load four different registers with distinct values, then read
        --        all four simultaneously and verify each port.
        -- =====================================================================
        report "=== TC-07: Simultaneous 4-port read ===" severity note;
        set_tc(current_tc, "TC-07: simultaneous 4-port read");

         -- Write a distinct sentinel into R0 so reg_a1 has a known,
        -- test-local value that is different from every other sentinel.
        wait until falling_edge(clock);
        reg_in     <= x"F00DF00D";      -- TC-15 R0 sentinel
        reg_in_sel <= 0;
        reg_store  <= '1';
        tick(clock);
        reg_store  <= '0';

        -- Write the four target registers sequentially
        for p in 0 to 3 loop
            wait until falling_edge(clock);
            reg_in     <= TC07_VALUES(p);
            reg_in_sel <= TC07_REGS(p);
            reg_store  <= '1';
            tick(clock);
            reg_store  <= '0';
        end loop;

        -- Point all four output selects simultaneously, then check
        wait until falling_edge(clock);
        reg_a_sel  <= TC07_REGS(0);     -- R2  -> reg_a
        reg_b_sel  <= TC07_REGS(1);     -- R4  -> reg_b
        reg_ax_sel <= TC07_REGS(2);     -- R6  -> reg_a1 redundant should not change value since reg_a1 always reads R0
        reg_a2_sel <= TC07_REGS(3);     -- R9  -> reg_a2
        tick(clock);

        check("TC-07 reg_a  (R2)", reg_a,  TC07_VALUES(0));
        check("TC-07 reg_b  (R4)", reg_b,  TC07_VALUES(1));
        check("TC-07 reg_a1 (R6)", reg_a1, x"F00DF00D");
        check("TC-07 reg_a2 (R9)", reg_a2, TC07_VALUES(3));

        -- =====================================================================
        -- TC-08  Simultaneous writes to DIFFERENT registers via both ports
        --        Both write ports fire in the same cycle but target different
        --        registers; both writes must succeed independently.
        -- =====================================================================
        report "=== TC-08: Simultaneous dual-port write to different registers ===" severity note;
        set_tc(current_tc, "TC-08: dual-port diff regs");

        wait until falling_edge(clock);
        reg_in       <= x"AAAAAAAA";
        reg_in_sel   <= 3;
        reg_store    <= '1';
        reg_ax_in    <= x"BBBBBBBB";
        reg_ax_sel   <= 7;
        reg_ax_store <= '1';
        tick(clock);
        reg_store    <= '0';
        reg_ax_store <= '0';

        -- Read R3 on reg_a and R7 on reg_b
        wait until falling_edge(clock);
        reg_a_sel <= 3;
        reg_b_sel <= 7;
        tick(clock);

        check("TC-08 R3 via reg_a", reg_a, x"AAAAAAAA");
        check("TC-08 R7 via reg_b", reg_b, x"BBBBBBBB");

        -- =====================================================================
        -- TC-09  Register retention
        --        Write all 16 registers, then read each one back to confirm no
        --        register lost its value during the surrounding reads/writes.
        -- =====================================================================
        report "=== TC-09: Register retention after population ===" severity note;
        set_tc(current_tc, "TC-09: register retention");

        -- Populate all registers with unique values
        for i in 0 to NUM_REGS - 1 loop
            wait until falling_edge(clock);
            reg_in     <= std_logic_vector(to_unsigned(i * 16#01010101#, 32));
            reg_in_sel <= i;
            reg_store  <= '1';
            tick(clock);
            reg_store  <= '0';
        end loop;

        -- Verify each register retained its value
        for i in 0 to NUM_REGS - 1 loop
            wait until falling_edge(clock);
            reg_a_sel <= i;
            tick(clock);
            check("TC-09 R" & integer'image(i),
                  reg_a,
                  std_logic_vector(to_unsigned(i * 16#01010101#, 32)));
        end loop;

        -- =====================================================================
        -- TC-10  Boundary data values: all zeros and all ones
        -- =====================================================================
        report "=== TC-10: Boundary values (0x00000000 / 0xFFFFFFFF) ===" severity note;
        set_tc(current_tc, "TC-10: boundary values");

        for i in 0 to NUM_REGS - 1 loop
            -- Write all zeros
            wait until falling_edge(clock);
            reg_in     <= x"00000000";
            reg_in_sel <= i;
            reg_store  <= '1';
            reg_a_sel  <= i;
            tick(clock);
            reg_store  <= '0';
            check("TC-10 R" & integer'image(i) & " all-zeros",
                  reg_a, x"00000000");

            -- Write all ones
            wait until falling_edge(clock);
            reg_in     <= x"FFFFFFFF";
            reg_in_sel <= i;
            reg_store  <= '1';
            tick(clock);
            reg_store  <= '0';
            check("TC-10 R" & integer'image(i) & " all-ones",
                  reg_a, x"FFFFFFFF");
        end loop;

        -- =====================================================================
        -- TC-11  Walking-1 pattern across all registers
        --        Each register receives a data word where a single bit is '1'
        --        cycling through bit positions 0..15 (mapped to register
        --        index).  This catches stuck-at faults on individual bit lines.
        -- =====================================================================
        report "=== TC-11: Walking-1 data pattern ===" severity note;
        set_tc(current_tc, "TC-11: walking-1 pattern");

        for i in 0 to NUM_REGS - 1 loop
            walking1_v := std_logic_vector(shift_left(to_unsigned(1, 32), i));

            wait until falling_edge(clock);
            reg_in     <= walking1_v;
            reg_in_sel <= i;
            reg_store  <= '1';
            reg_a_sel  <= i;
            tick(clock);
            reg_store  <= '0';

            check("TC-11 R" & integer'image(i) & " walking-1",
                  reg_a, walking1_v);
        end loop;

        -- =====================================================================
        -- TC-12  R0 as index / address register
        --        The SH2 uses R0 as the index register in @(R0, Rn) indirect
        --        indexed addressing.  Verify that R0 can be written and
        --        simultaneously read on BOTH the ALU port (reg_a) and the
        --        address port (reg_a2) to simulate the hardware reading R0 as
        --        an index offset while Rn is read as a base address.
        -- =====================================================================
        report "=== TC-12: R0 as index register (dual read) ===" severity note;
        set_tc(current_tc, "TC-12: R0 index register");

        -- Write R0 (index) = 0x00000010
        wait until falling_edge(clock);
        reg_in     <= x"00000010";
        reg_in_sel <= 0;
        reg_store  <= '1';
        tick(clock);
        reg_store  <= '0';

        -- Write R3 (base) = 0xA0000000
        wait until falling_edge(clock);
        reg_in     <= x"A0000000";
        reg_in_sel <= 3;
        reg_store  <= '1';
        tick(clock);
        reg_store  <= '0';

        -- Simultaneously read R0 on reg_a and R3 on reg_a2
        -- (mirrors the hardware forming the effective address R0 + Rn)
        wait until falling_edge(clock);
        reg_a_sel  <= 0;        -- R0 index  on ALU port
        reg_a2_sel <= 3;        -- Rn base   on address port 2
        tick(clock);

        check("TC-12 R0 (index) via reg_a",  reg_a,  x"00000010");
        check("TC-12 R3 (base)  via reg_a2", reg_a2, x"A0000000");

        -- Verify the computed effective address R0 + R3
        eff_addr_v := unsigned(reg_a) + unsigned(reg_a2);
        if eff_addr_v = x"A0000010" then
            report "PASS  [TC-12 effective address R0+R3 = 0xA0000010]"
                severity note;
            scoreboard.increment_pass;
        else
            report "FAIL  [TC-12 effective address R0+R3]"
                   & "  expected=0xA0000010  got=0x"
                   & to_hstring(std_logic_vector(eff_addr_v))
                severity error;
            scoreboard.increment_fail;
        end if;

        -- =====================================================================
        -- TC-13  R15 as hardware stack pointer (SP)
        --        The SH2 uses R15 as the stack pointer during exception
        --        handling.  reg_a1 is hardwired to R0, so SP updates written
        --        via the ax port are verified through reg_a instead.
        -- =====================================================================
        report "=== TC-13: R15 as hardware stack pointer ===" severity note;
        set_tc(current_tc, "TC-13: R15 stack pointer");

        -- Set R15 = 0xFF000100 (plausible top-of-stack address)
        wait until falling_edge(clock);
        reg_in     <= x"FF000100";
        reg_in_sel <= 15;
        reg_store  <= '1';
        tick(clock);
        reg_store  <= '0';

        -- Confirm R15 is readable on reg_a
        wait until falling_edge(clock);
        reg_a_sel <= 15;
        tick(clock);
        check("TC-13 R15 SP via reg_a", reg_a, x"FF000100");

        -- Simulate a push: address unit writes SP - 4 back via address port
        wait until falling_edge(clock);
        reg_ax_in    <= x"FF0000FC";    -- SP - 4
        reg_ax_sel   <= 15;
        reg_ax_store <= '1';
        tick(clock);
        reg_ax_store <= '0';

        -- reg_a1 is hardwired to R0 so we cannot use it to read R15.
        -- Verify the ax write landed correctly via reg_a instead.
        wait until falling_edge(clock);
        reg_a_sel <= 15;
        tick(clock);
        check("TC-13 R15 SP after push (via reg_a)", reg_a, x"FF0000FC");

        -- Simulate a pop: main port restores SP + 4
        wait until falling_edge(clock);
        reg_in     <= x"FF000100";
        reg_in_sel <= 15;
        reg_store  <= '1';
        tick(clock);
        reg_store  <= '0';

        wait until falling_edge(clock);
        reg_a_sel <= 15;
        tick(clock);
        check("TC-13 R15 SP after pop (via reg_a)", reg_a, x"FF000100");

        -- =====================================================================
        -- TC-14  Write-port conflict: both ports target the SAME register
        --        simultaneously.  The test checks that a deterministic value
        --        appears (no metastability / undefined output) and reports
        --        whether the main port won.
        -- =====================================================================
        report "=== TC-14: Write-port conflict on same register ===" severity note;
        set_tc(current_tc, "TC-14: write-port conflict");

        wait until falling_edge(clock);
        reg_in       <= x"11111111";    -- main port data
        reg_in_sel   <= 10;
        reg_store    <= '1';
        reg_ax_in    <= x"22222222";    -- address port data
        reg_ax_sel   <= 10;
        reg_ax_store <= '1';
        tick(clock);
        reg_store    <= '0';
        reg_ax_store <= '0';

        wait until falling_edge(clock);
        reg_a_sel <= 10;
        tick(clock);

        -- Check that the output is one of the two valid candidates (not X/U)
        -- Main port wins since highest precedence!
        if reg_a = x"11111111" then
            report "INFO  [TC-14] main port wins on conflict: R10 = 0x11111111"
                severity note;
            scoreboard.increment_pass;
        else
            report "FAIL  [TC-14] conflict produced undefined/unexpected value: 0x"
                   & to_hstring(reg_a)
                severity error;
            scoreboard.increment_fail;
        end if;

        -- =====================================================================
        -- TC-15  Read-port independence
        --        Changing reg_a_sel must not alter the value seen on reg_b,
        --        reg_a1, or reg_a2, and vice-versa.
        -- =====================================================================
        report "=== TC-15: Read-port independence ===" severity note;
        set_tc(current_tc, "TC-15: read-port independence");

        -- Write a distinct sentinel into R0 so reg_a1 has a known,
        -- test-local value that is different from every other sentinel.
        wait until falling_edge(clock);
        reg_in     <= x"F00DF00D";      -- TC-15 R0 sentinel
        reg_in_sel <= 0;
        reg_store  <= '1';
        tick(clock);
        reg_store  <= '0';

        -- Populate the four target registers with distinct sentinels
        for p in 0 to 3 loop
            wait until falling_edge(clock);
            reg_in     <= TC15_SENTINELS(p);
            reg_in_sel <= TC15_REGS(p);
            reg_store  <= '1';
            tick(clock);
            reg_store  <= '0';
        end loop;

        -- Lock reg_b, reg_ax, reg_a2 onto their fixed targets
        wait until falling_edge(clock);
        reg_b_sel  <= TC15_REGS(1);
        reg_ax_sel <= TC15_REGS(2);
        reg_a2_sel <= TC15_REGS(3);
        tick(clock);

        -- Cycle reg_a_sel through all 16 registers; the other three ports
        -- must report the same value on every cycle
        -- reg_a1 is hardwired to R0, so it must always read x"F00DF00D".
        for i in 0 to NUM_REGS - 1 loop
            wait until falling_edge(clock);
            reg_a_sel <= i;
            tick(clock);
            check("TC-15 reg_b  stable (reg_a_sel=" & integer'image(i) & ")",
                  reg_b,  TC15_SENTINELS(1));
            check("TC-15 reg_a1 = R0  (reg_a_sel=" & integer'image(i) & ")",
                  reg_a1, x"F00DF00D");
            check("TC-15 reg_a2 stable (reg_a_sel=" & integer'image(i) & ")",
                  reg_a2, TC15_SENTINELS(3));
        end loop;

        -- =====================================================================
        -- TC-16  Sequential ALU-style operation
        --        Simulates a two-operand ALU instruction: read Ra and Rb,
        --        compute Ra + Rb externally, write result back to Ra via the
        --        main write port.  Exercises the typical SH2 "ADD Rm, Rn"
        --        data-path.
        -- =====================================================================
        report "=== TC-16: Simulated ALU ADD Rm, Rn (reg_a + reg_b -> Rn) ===" severity note;
        set_tc(current_tc, "TC-16: ALU ADD Rm Rn");

        -- Load R6 = 100 (0x64), R7 = 150 (0x96)
        wait until falling_edge(clock);
        reg_in     <= x"00000064";
        reg_in_sel <= 6;
        reg_store  <= '1';
        tick(clock);
        reg_store  <= '0';

        wait until falling_edge(clock);
        reg_in     <= x"00000096";
        reg_in_sel <= 7;
        reg_store  <= '1';
        tick(clock);
        reg_store  <= '0';

        -- Read R6 -> reg_a and R7 -> reg_b simultaneously
        wait until falling_edge(clock);
        reg_a_sel <= 6;
        reg_b_sel <= 7;
        tick(clock);

        -- Compute the sum and write it back to R6
        sum_v := std_logic_vector(unsigned(reg_a) + unsigned(reg_b));

        wait until falling_edge(clock);
        reg_in     <= sum_v;
        reg_in_sel <= 6;
        reg_store  <= '1';
        reg_a_sel  <= 6;
        tick(clock);
        reg_store  <= '0';

        -- 100 + 150 = 250 = 0xFA
        check("TC-16 R6 after ADD (100+150=250)", reg_a, x"000000FA");

        -- =====================================================================
        -- TC-17  Post-increment / pre-decrement address update
        --        SH2 @Rn+ and @-Rn modes update Rn via the address unit.
        --        reg_a1 is hardwired to R0, so the updated Rn value is
        --        verified via reg_a after each ax write.
        -- =====================================================================
        report "=== TC-17: Simulated @Rn+ and @-Rn address update ==="
            severity note;
        set_tc(current_tc, "TC-17: post/pre inc/dec addr");

        -- Set R9 = 0x20000000; post-increment by 2 (word access, @Rn+)
        wait until falling_edge(clock);
        reg_in     <= x"20000000";
        reg_in_sel <= 9;
        reg_store  <= '1';
        tick(clock);
        reg_store  <= '0';

        -- Write Rn + 2 back via address port (@Rn+ word)
        wait until falling_edge(clock);
        reg_ax_sel   <= 9;
        reg_ax_in    <= x"20000002";    -- Rn + 2
        reg_ax_store <= '1';
        tick(clock);
        reg_ax_store <= '0';

        -- reg_a1 is hardwired to R0; read R9 back via reg_a to verify the write
        wait until falling_edge(clock);
        reg_a_sel <= 9;
        tick(clock);
        check("TC-17 R9 post-increment (word)", reg_a, x"20000002");

        -- Pre-decrement: set R9 = 0x20000010, then write Rn - 4 (longword, @-Rn)
        wait until falling_edge(clock);
        reg_in     <= x"20000010";
        reg_in_sel <= 9;
        reg_store  <= '1';
        tick(clock);
        reg_store  <= '0';

        wait until falling_edge(clock);
        reg_ax_sel   <= 9;
        reg_ax_in    <= x"2000000C";    -- Rn - 4
        reg_ax_store <= '1';
        tick(clock);
        reg_ax_store <= '0';

        wait until falling_edge(clock);
        reg_a_sel <= 9;
        tick(clock);
        check("TC-17 R9 pre-decrement (longword)", reg_a, x"2000000C");

        -- =====================================================================
        -- TC-18  R0 displacement addressing
        --        Several SH2 instructions use R0 as a fixed source/destination
        --        (e.g., MOV.B @(R0,Rn), Rm).  Verify that R0 can be written
        --        via the address port and simultaneously read on the ALU port.
        -- =====================================================================
        report "=== TC-18: R0 address-port write / ALU-port read ===" severity note;
        set_tc(current_tc, "TC-18: R0 displacement addr");

        -- Write R0 via address port (address block computes displacement)
        wait until falling_edge(clock);
        reg_ax_in    <= x"00000008";    -- displacement offset loaded into R0
        reg_ax_sel   <= 0;              -- R0
        reg_ax_store <= '1';
        reg_a_sel    <= 0;
        tick(clock);
        reg_ax_store <= '0';

        check("TC-18 R0 via reg_a  after ax write", reg_a,  x"00000008");
        check("TC-18 R0 via reg_a1 after ax write", reg_a1, x"00000008");

        -- =====================================================================
        -- TC-19  Non-destructive repeated read
        --        Read the same register multiple times on the same port and
        --        verify the value is stable (no self-modification on read).
        -- =====================================================================
        report "=== TC-19: Non-destructive repeated read ===" severity note;
        set_tc(current_tc, "TC-19: non-destructive read");

        -- Write R11 = 0xBADC0FFE
        wait until falling_edge(clock);
        reg_in     <= x"BADC0FFE";
        reg_in_sel <= 11;
        reg_store  <= '1';
        reg_a_sel  <= 11;
        tick(clock);
        reg_store  <= '0';

        for rep in 1 to 8 loop
            tick(clock);
            check("TC-19 R11 read #" & integer'image(rep),
                  reg_a, x"BADC0FFE");
        end loop;

        -- =====================================================================
        -- TC-20  All-register independence: confirm no aliasing
        --        Write a unique value to every register, then read all of them
        --        back in REVERSE order to confirm no register aliases another.
        -- =====================================================================
        report "=== TC-20: All-register independence (reverse read-back) ===" severity note;
        set_tc(current_tc, "TC-20: all-reg independence");

        -- Write all 16 registers with distinct values
        for i in 0 to NUM_REGS - 1 loop
            data_v := std_logic_vector(
                          unsigned'(x"DEAD0000") + to_unsigned(i * 16#100#, 32));
            wait until falling_edge(clock);
            reg_in     <= data_v;
            reg_in_sel <= i;
            reg_store  <= '1';
            tick(clock);
            reg_store  <= '0';
        end loop;

        -- Read back in reverse order to catch any address-line aliasing
        for i in NUM_REGS - 1 downto 0 loop
            data_v := std_logic_vector(
                          unsigned'(x"DEAD0000") + to_unsigned(i * 16#100#, 32));
            wait until falling_edge(clock);
            reg_a_sel <= i;
            tick(clock);
            check("TC-20 R" & integer'image(i) & " reverse read",
                  reg_a, data_v);
        end loop;

        -- =====================================================================
        -- Final summary
        -- =====================================================================
        report "======================================================" severity note;
        report "TEST SUMMARY:  PASS=" & integer'image(scoreboard.get_pass)
               & "  FAIL=" & integer'image(scoreboard.get_fail)
            severity note;
        report "======================================================" severity note;

        if scoreboard.get_fail = 0 then
            report "ALL TESTS PASSED" severity note;
        else
            report integer'image(scoreboard.get_fail) & " TEST(S) FAILED"
                severity failure;
        end if;

        wait;   -- stop simulation
    end process stim;

end architecture sim;