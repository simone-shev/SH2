library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MMU_tb is
end entity MMU_tb;

architecture tb of MMU_tb is

    ---------------------------------------------------------------------------
    -- DUT signals
    ---------------------------------------------------------------------------
    signal RW        : std_logic := '1';
    signal LAB       : std_logic_vector(31 downto 0) := (others => '0');
    signal DB        : std_logic_vector(31 downto 0);
    signal CS        : std_logic := '1';
    signal clock     : std_logic := '0';
    signal PAB       : std_logic_vector(41 downto 0);
    signal SegFault  : std_logic;
    signal ProtFault : std_logic;
    signal RW_output : std_logic;

    -- Testbench driver for the bidirectional data bus.
    -- db_drive feeds DB; set to Z when the MMU should drive (reads).
    signal db_drive : std_logic_vector(31 downto 0) := (others => 'Z');

    constant CLK_PER : time := 20 ns;
    constant SETTLE  : time := 2 ns;
    signal   done    : boolean := false;

    ---------------------------------------------------------------------------
    -- Mask constants (register values for various segment sizes)
    --
    -- For a segment of size 2^s the register value is:
    --   bits 31:s  = 1   (tag)
    --   bits s-1:0 = 0   (offset passes through)
    ---------------------------------------------------------------------------
    constant MASK_2_10 : std_logic_vector(31 downto 0) := x"FFFFFC00"; -- minimum
    constant MASK_2_14 : std_logic_vector(31 downto 0) := x"FFFFC000";
    constant MASK_2_16 : std_logic_vector(31 downto 0) := x"FFFF0000";
    constant MASK_2_20 : std_logic_vector(31 downto 0) := x"FFF00000";
    constant MASK_2_32 : std_logic_vector(31 downto 0) := x"00000000"; -- maximum

    ---------------------------------------------------------------------------
    -- Status-word helpers
    --
    --   bit 31 = U  (used)         -- set by MMU
    --   bit 30 = D  (dirty)        -- set by MMU
    --   bit 29 = WP (write-protect)-- CPU only
    --   bit 28 = F  (fault)        -- set by MMU
    --   bit 27 = E  (enabled)      -- CPU only
    --   bits 15:0 = segment index  -- CPU only
    ---------------------------------------------------------------------------
    constant U_BIT  : natural := 31;
    constant D_BIT  : natural := 30;
    constant WP_BIT : natural := 29;
    constant F_BIT  : natural := 28;
    constant E_BIT  : natural := 27;

    -- Convenience: build a status/index word
    function make_status(
        e     : std_logic;
        wp    : std_logic;
        index : integer
    ) return std_logic_vector is
        variable r : std_logic_vector(31 downto 0) := (others => '0');
    begin
        r(E_BIT)  := e;
        r(WP_BIT) := wp;
        r(15 downto 0) := std_logic_vector(to_unsigned(index, 16));
        return r;
    end function;

    ---------------------------------------------------------------------------
    -- Expected-PAB computation (mirrors the translation datapath)
    ---------------------------------------------------------------------------
    function calc_pab(
        log_addr : std_logic_vector(31 downto 0);
        physbase : std_logic_vector(31 downto 0);
        mask_reg : std_logic_vector(31 downto 0)
    ) return std_logic_vector is
        variable result : std_logic_vector(41 downto 0);
        variable offset : std_logic_vector(21 downto 0);
    begin
        offset := log_addr(31 downto 10) and not mask_reg(31 downto 10);
        result(41 downto 10) := physbase or ("0000000000" & offset);
        result(9 downto 0)   := log_addr(9 downto 0);
        return result;
    end function;

begin

    ---------------------------------------------------------------------------
    -- Clock generator
    ---------------------------------------------------------------------------
    clock <= not clock after CLK_PER / 2 when not done else '0';

    ---------------------------------------------------------------------------
    -- Bidirectional bus: testbench drives db_drive, DUT drives DB via inout
    ---------------------------------------------------------------------------
    DB <= db_drive;

    ---------------------------------------------------------------------------
    -- DUT instantiation
    ---------------------------------------------------------------------------
    uut : entity work.MMU
        port map (
            RW        => RW,
            LAB       => LAB,
            DB        => DB,
            CS        => CS,
            clock     => clock,
            PAB       => PAB,
            SegFault  => SegFault,
            ProtFault => ProtFault,
            RW_output => RW_output
        );

    ---------------------------------------------------------------------------
    -- Stimulus process
    ---------------------------------------------------------------------------
    stim : process

        variable pass_cnt : integer := 0;
        variable fail_cnt : integer := 0;

        -----------------------------------------------------------------------
        -- Assertion helper: tracks pass/fail counts
        -----------------------------------------------------------------------
        procedure check(cond : boolean; msg : string) is
        begin
            if cond then
                pass_cnt := pass_cnt + 1;
            else
                fail_cnt := fail_cnt + 1;
                report "FAIL: " & msg severity error;
            end if;
        end procedure;

        -----------------------------------------------------------------------
        -- Write one of the 16 MMU registers.
        -- seg    = 0..3  (which segment slot)
        -- offset = 0..3  (0=phys, 1=logbase, 2=mask, 3=status/index)
        -----------------------------------------------------------------------
        procedure write_reg(
            seg    : integer;
            offset : integer;
            data   : std_logic_vector(31 downto 0)
        ) is
        begin
            CS  <= '0';
            RW  <= '0';
            LAB <= (others => '0');
            LAB(3 downto 2) <= std_logic_vector(to_unsigned(seg, 2));
            LAB(1 downto 0) <= std_logic_vector(to_unsigned(offset, 2));
            db_drive <= data;
            wait until rising_edge(clock);
            wait for SETTLE;
        end procedure;

        -----------------------------------------------------------------------
        -- Read one of the 16 MMU registers.
        -- After this returns, DB holds the register value.  The bus stays
        -- set up (CS='0', RW='1') until the next procedure call changes it,
        -- so the caller can inspect DB before the next wait.
        -----------------------------------------------------------------------
        procedure read_reg(
            seg    : integer;
            offset : integer
        ) is
        begin
            db_drive <= (others => 'Z');  -- release bus so MMU can drive
            CS  <= '0';
            RW  <= '1';
            LAB <= (others => '0');
            LAB(3 downto 2) <= std_logic_vector(to_unsigned(seg, 2));
            LAB(1 downto 0) <= std_logic_vector(to_unsigned(offset, 2));
            wait until rising_edge(clock);
            wait for SETTLE;
        end procedure;

        -----------------------------------------------------------------------
        -- Load a full four-register segment descriptor.
        -- Writes are ordered: phys, logbase, mask, then status last (so E
        -- is set only after the other fields are valid).
        -----------------------------------------------------------------------
        procedure load_seg(
            seg      : integer;
            physbase : std_logic_vector(31 downto 0);
            logbase  : std_logic_vector(31 downto 0);
            mask     : std_logic_vector(31 downto 0);
            status   : std_logic_vector(31 downto 0)
        ) is
        begin
            write_reg(seg, 0, physbase);
            write_reg(seg, 1, logbase);
            write_reg(seg, 2, mask);
            write_reg(seg, 3, status);   -- E goes live here
        end procedure;

        -----------------------------------------------------------------------
        -- Disable a segment (clear all status bits including E).
        -----------------------------------------------------------------------
        procedure disable_seg(seg : integer) is
        begin
            write_reg(seg, 3, x"00000000");
        end procedure;

        -----------------------------------------------------------------------
        -- Disable all four segments.
        -----------------------------------------------------------------------
        procedure disable_all is
        begin
            for i in 0 to 3 loop
                disable_seg(i);
            end loop;
        end procedure;

        -----------------------------------------------------------------------
        -- Present a logical address for translation (combinational path).
        -- Does NOT advance the clock — PAB/faults settle after SETTLE.
        -----------------------------------------------------------------------
        procedure translate(
            addr     : std_logic_vector(31 downto 0);
            is_write : boolean := false
        ) is
        begin
            CS       <= '1';
            LAB      <= addr;
            db_drive <= (others => 'Z');
            if is_write then
                RW <= '0';
            else
                RW <= '1';
            end if;
            wait for SETTLE;
        end procedure;

        -----------------------------------------------------------------------
        -- Advance one clock edge so the clocked process can latch status-bit
        -- updates (U, D, F).  Call after translate when you need to inspect
        -- status afterwards.
        -----------------------------------------------------------------------
        procedure latch is
        begin
            wait until rising_edge(clock);
            wait for SETTLE;
        end procedure;

        -----------------------------------------------------------------------
        -- Idle: release all buses, return to translation mode, advance one
        -- clock cycle.  Useful as a separator between test groups.
        -----------------------------------------------------------------------
        procedure idle is
        begin
            CS       <= '1';
            RW       <= '1';
            LAB      <= (others => '0');
            db_drive <= (others => 'Z');
            wait until rising_edge(clock);
            wait for SETTLE;
        end procedure;

    begin
        -- let the clock start cleanly
        wait until rising_edge(clock);
        report "=== MMU Testbench Start ===";

        -----------------------------------------------------------------------
        -- TEST 1: Initial state — no segments enabled, any address faults
        -----------------------------------------------------------------------
        report "--- Test 1: Initial state ---";

        translate(x"00000000");
        check(SegFault = '0',  "T1.1  SegFault asserted at reset (active low)");
        check(ProtFault = '1', "T1.2  ProtFault deasserted at reset");
        check(RW_output = '1', "T1.3  RW_output defaults to read on miss");

        idle;

        -----------------------------------------------------------------------
        -- TEST 2: Register write and read-back for all four segments
        -----------------------------------------------------------------------
        report "--- Test 2: Register write / read-back ---";

        load_seg(0, x"ABCD0000", x"00001000", MASK_2_10, make_status('1','0', 1));
        load_seg(1, x"12340000", x"50000000", MASK_2_20, make_status('1','0', 2));
        load_seg(2, x"DEAD0000", x"80000000", MASK_2_16, make_status('1','1', 3));
        load_seg(3, x"FACE0000", x"C0000000", MASK_2_14, make_status('1','0', 4));

        -- Segment 0: full read-back
        read_reg(0, 0);
        check(DB = x"ABCD0000", "T2.1  Seg0 phys_base");
        read_reg(0, 1);
        check(DB = x"00001000", "T2.2  Seg0 log_base");
        read_reg(0, 2);
        check(DB = MASK_2_10,   "T2.3  Seg0 mask");
        read_reg(0, 3);
        check(DB = make_status('1','0', 1), "T2.4  Seg0 status/index");

        -- Segment 1: spot-check
        read_reg(1, 0);
        check(DB = x"12340000", "T2.5  Seg1 phys_base");
        read_reg(1, 2);
        check(DB = MASK_2_20,   "T2.6  Seg1 mask");

        -- Segment 2: spot-check
        read_reg(2, 0);
        check(DB = x"DEAD0000", "T2.7  Seg2 phys_base");
        read_reg(2, 3);
        check(DB = make_status('1','1', 3), "T2.8  Seg2 status (WP set)");

        -- Segment 3: spot-check
        read_reg(3, 1);
        check(DB = x"C0000000", "T2.9  Seg3 log_base");
        read_reg(3, 2);
        check(DB = MASK_2_14,   "T2.10 Seg3 mask");

        idle;

        -----------------------------------------------------------------------
        -- TEST 3: Basic translation hit — minimum segment (2^10)
        --
        -- Seg 0: phys=ABCD0000, log=00001000, mask=FFFFFC00 (2^10)
        -- Segment covers logical 0x00001000..0x000013FF
        -- With mask all-ones, only LAB(9:0) is offset, so:
        --   PAB(41:10) = phys_base,  PAB(9:0) = LAB(9:0)
        -----------------------------------------------------------------------
        report "--- Test 3: Hit on min segment (2^10) ---";

        -- At base address (offset = 0)
        translate(x"00001000");
        check(SegFault  = '1', "T3.1  SegFault deasserted on hit");
        check(ProtFault = '1', "T3.2  No prot fault on read");
        check(RW_output = '1', "T3.3  RW_output = read");
        check(PAB = calc_pab(x"00001000", x"ABCD0000", MASK_2_10),
              "T3.4  PAB at base of min segment");

        -- At maximum offset (0x3FF = 1023)
        translate(x"000013FF");
        check(SegFault = '1', "T3.5  Hit at max offset");
        check(PAB = calc_pab(x"000013FF", x"ABCD0000", MASK_2_10),
              "T3.6  PAB at max offset of min segment");

        idle;

        -----------------------------------------------------------------------
        -- TEST 4: SegFault on miss
        --
        -- Loaded segments are at 0x00001xxx, 0x500xxxxx, 0x8000xxxx,
        -- 0xC000xxxx.  Address 0x20000000 misses all four.
        -----------------------------------------------------------------------
        report "--- Test 4: SegFault on miss ---";

        translate(x"20000000");
        check(SegFault  = '0', "T4.1  SegFault asserted on miss");
        check(ProtFault = '1', "T4.2  No prot fault on miss");
        check(RW_output = '1', "T4.3  RW_output defaults to read on miss");

        -- Also miss on write
        translate(x"20000000", true);
        check(SegFault = '0', "T4.4  SegFault asserted on write miss");

        idle;

        -----------------------------------------------------------------------
        -- TEST 5: Translation with 2^20 segment and non-zero offset
        --
        -- Seg 1: phys=12340000, log=50000000, mask=FFF00000 (2^20)
        -- Segment covers logical 0x50000000..0x500FFFFF
        -- Offset = LAB(19:0).  In PAB(41:10), LAB(19:10) fills the
        -- low 10 bits of the 32-bit field; LAB(9:0) fills PAB(9:0).
        -----------------------------------------------------------------------
        report "--- Test 5: 2^20 segment with offset ---";

        -- At base (offset 0)
        translate(x"50000000");
        check(SegFault = '1', "T5.1  Hit at 2^20 base");
        check(PAB = calc_pab(x"50000000", x"12340000", MASK_2_20),
              "T5.2  PAB at 2^20 base");

        -- With a non-trivial offset
        translate(x"50080000");
        check(SegFault = '1', "T5.3  Hit with offset");
        check(PAB = calc_pab(x"50080000", x"12340000", MASK_2_20),
              "T5.4  PAB with 2^20 offset");

        -- At max offset (0xFFFFF)
        translate(x"500FFFFF");
        check(SegFault = '1', "T5.5  Hit at max 2^20 offset");
        check(PAB = calc_pab(x"500FFFFF", x"12340000", MASK_2_20),
              "T5.6  PAB at max 2^20 offset");

        idle;

        -----------------------------------------------------------------------
        -- TEST 6: 2^14 segment
        --
        -- Seg 3: phys=FACE0000, log=C0000000, mask=FFFFC000 (2^14)
        -- Segment covers logical 0xC0000000..0xC0003FFF
        -----------------------------------------------------------------------
        report "--- Test 6: 2^14 segment ---";

        translate(x"C0000000");
        check(SegFault = '1', "T6.1  Hit at 2^14 base");
        check(PAB = calc_pab(x"C0000000", x"FACE0000", MASK_2_14),
              "T6.2  PAB at 2^14 base");

        translate(x"C0003FFF");
        check(SegFault = '1', "T6.3  Hit at 2^14 max offset");
        check(PAB = calc_pab(x"C0003FFF", x"FACE0000", MASK_2_14),
              "T6.4  PAB at 2^14 max offset");

        -- Just outside the segment: 0xC0004000 (bit 14 set — differs in tag)
        translate(x"C0004000");
        check(SegFault = '0', "T6.5  Miss just outside 2^14 segment");

        idle;

        -----------------------------------------------------------------------
        -- TEST 7: Write protection — ProtFault
        --
        -- Seg 2: WP=1, E=1, phys=DEAD0000, log=80000000, mask=FFFF0000
        -----------------------------------------------------------------------
        report "--- Test 7: Write protection ---";

        -- Read to WP segment: no fault
        translate(x"80000000");
        check(SegFault  = '1', "T7.1  Hit on read to WP seg");
        check(ProtFault = '1', "T7.2  No prot fault on read to WP seg");
        check(RW_output = '1', "T7.3  RW_output = read");

        -- Write to WP segment: ProtFault asserted
        translate(x"80000000", true);
        check(SegFault  = '1', "T7.4  Still a hit (segment matches)");
        check(ProtFault = '0', "T7.5  ProtFault asserted on write to WP seg");
        check(RW_output = '1', "T7.6  RW_output stays read (write blocked)");

        idle;

        -----------------------------------------------------------------------
        -- TEST 8: U bit set on read
        --
        -- Reload seg 0 with clean status, do a read translation, verify U.
        -----------------------------------------------------------------------
        report "--- Test 8: U bit on read ---";

        write_reg(0, 3, make_status('1', '0', 1));  -- E=1, clear U/D/F

        translate(x"00001000");                       -- read hit
        latch;                                        -- clock edge latches U

        read_reg(0, 3);
        check(DB(U_BIT) = '1', "T8.1  U set after read");
        check(DB(D_BIT) = '0', "T8.2  D not set after read");
        check(DB(F_BIT) = '0', "T8.3  F not set after read");

        idle;

        -----------------------------------------------------------------------
        -- TEST 9: D bit set on write (non-WP segment)
        -----------------------------------------------------------------------
        report "--- Test 9: D bit on write ---";

        write_reg(0, 3, make_status('1', '0', 1));  -- clean

        translate(x"00001000", true);                 -- write hit, no WP
        latch;

        read_reg(0, 3);
        check(DB(U_BIT) = '1', "T9.1  U set after write");
        check(DB(D_BIT) = '1', "T9.2  D set after write");
        check(DB(F_BIT) = '0', "T9.3  F not set (no WP)");

        idle;

        -----------------------------------------------------------------------
        -- TEST 10: F bit set on protection fault
        --
        -- Seg 2 has WP=1.  Write to it, then read back status.
        -----------------------------------------------------------------------
        report "--- Test 10: F bit on prot fault ---";

        -- Reload seg 2 with clean U/D/F but WP=1
        write_reg(2, 3, make_status('1', '1', 3));

        translate(x"80000000", true);                 -- write to WP seg
        check(ProtFault = '0', "T10.1 ProtFault asserted");
        latch;

        read_reg(2, 3);
        check(DB(F_BIT) = '1', "T10.2 F bit set after prot fault");
        check(DB(U_BIT) = '1', "T10.3 U also set (access occurred)");
        check(DB(D_BIT) = '0', "T10.4 D not set (write was blocked)");

        idle;

        -----------------------------------------------------------------------
        -- TEST 11: E bit disabled — segment should not match
        -----------------------------------------------------------------------
        report "--- Test 11: E=0 suppresses matching ---";

        disable_all;

        -- Load seg 0 with E=0
        write_reg(0, 0, x"ABCD0000");
        write_reg(0, 1, x"00001000");
        write_reg(0, 2, MASK_2_10);
        write_reg(0, 3, make_status('0', '0', 1));   -- E=0

        translate(x"00001000");
        check(SegFault = '0', "T11.1 SegFault when E=0 (segment disabled)");

        -- Enable it, same address should now hit
        write_reg(0, 3, make_status('1', '0', 1));   -- E=1
        translate(x"00001000");
        check(SegFault = '1', "T11.2 Hit after enabling segment");

        idle;

        -----------------------------------------------------------------------
        -- TEST 12: All four segments active, correct routing
        --
        -- Each segment at a non-overlapping logical range, each with a
        -- distinct physical base.  Verify each address routes to the
        -- correct physical base.
        -----------------------------------------------------------------------
        report "--- Test 12: All 4 segments active ---";

        disable_all;

        load_seg(0, x"AA000000", x"00001000", MASK_2_10, make_status('1','0', 10));
        load_seg(1, x"BB000000", x"50000000", MASK_2_20, make_status('1','0', 20));
        load_seg(2, x"CC000000", x"80000000", MASK_2_16, make_status('1','0', 30));
        load_seg(3, x"DD000000", x"C0000000", MASK_2_14, make_status('1','0', 40));

        -- Hit seg 0
        translate(x"00001000");
        check(SegFault = '1', "T12.1 Seg0 hit");
        check(PAB = calc_pab(x"00001000", x"AA000000", MASK_2_10),
              "T12.2 Seg0 PAB correct");

        -- Hit seg 1
        translate(x"50055000");
        check(SegFault = '1', "T12.3 Seg1 hit");
        check(PAB = calc_pab(x"50055000", x"BB000000", MASK_2_20),
              "T12.4 Seg1 PAB correct");

        -- Hit seg 2
        translate(x"80005000");
        check(SegFault = '1', "T12.5 Seg2 hit");
        check(PAB = calc_pab(x"80005000", x"CC000000", MASK_2_16),
              "T12.6 Seg2 PAB correct");

        -- Hit seg 3
        translate(x"C0002000");
        check(SegFault = '1', "T12.7 Seg3 hit");
        check(PAB = calc_pab(x"C0002000", x"DD000000", MASK_2_14),
              "T12.8 Seg3 PAB correct");

        -- Miss (address not in any segment)
        translate(x"30000000");
        check(SegFault = '0', "T12.9 Miss when 4 segs active");

        idle;

        -----------------------------------------------------------------------
        -- TEST 13: Maximum segment (2^32)
        --
        -- mask = 00000000 → every bit of LAB is offset, every address hits.
        -- phys_base upper 10 bits provide the extra physical range.
        -----------------------------------------------------------------------
        report "--- Test 13: Maximum segment (2^32) ---";

        disable_all;

        load_seg(0, x"FF000000", x"00000000", MASK_2_32, make_status('1','0', 99));

        translate(x"00000000");
        check(SegFault = '1', "T13.1 Hit at addr 0");
        check(PAB = calc_pab(x"00000000", x"FF000000", MASK_2_32),
              "T13.2 PAB at addr 0");

        translate(x"DEADBEEF");
        check(SegFault = '1', "T13.3 Hit at arbitrary addr");
        check(PAB = calc_pab(x"DEADBEEF", x"FF000000", MASK_2_32),
              "T13.4 PAB at arbitrary addr");

        translate(x"FFFFFFFF");
        check(SegFault = '1', "T13.5 Hit at max addr");
        check(PAB = calc_pab(x"FFFFFFFF", x"FF000000", MASK_2_32),
              "T13.6 PAB at max addr");

        idle;

        -----------------------------------------------------------------------
        -- TEST 14: RW_output tracks RW on hit, defaults to read on miss
        -----------------------------------------------------------------------
        report "--- Test 14: RW_output ---";

        -- Seg 0 still loaded as 2^32, no WP
        translate(x"12345678");           -- read
        check(RW_output = '1', "T14.1 RW_output=1 on read hit");

        translate(x"12345678", true);     -- write
        check(RW_output = '0', "T14.2 RW_output=0 on write hit");

        -- Disable all → miss
        disable_all;
        translate(x"12345678");
        check(RW_output = '1', "T14.3 RW_output=1 on miss (read default)");

        translate(x"12345678", true);
        check(RW_output = '1', "T14.4 RW_output=1 on write miss (blocked)");

        idle;

        -----------------------------------------------------------------------
        -- TEST 15: Read-back status after cumulative MMU updates
        --
        -- Load clean → read (sets U) → verify → write (sets D) → verify.
        -----------------------------------------------------------------------
        report "--- Test 15: Cumulative status updates ---";

        disable_all;
        load_seg(0, x"AA000000", x"00001000", MASK_2_10, make_status('1','0', 1));

        -- Verify clean
        read_reg(0, 3);
        check(DB(U_BIT) = '0', "T15.1 U initially clear");
        check(DB(D_BIT) = '0', "T15.2 D initially clear");
        check(DB(F_BIT) = '0', "T15.3 F initially clear");

        -- Read translation → U set
        translate(x"00001000");
        latch;
        read_reg(0, 3);
        check(DB(U_BIT) = '1', "T15.4 U set after read");
        check(DB(D_BIT) = '0', "T15.5 D still clear");

        -- Write translation → D set (U stays)
        translate(x"00001000", true);
        latch;
        read_reg(0, 3);
        check(DB(U_BIT) = '1', "T15.6 U still set");
        check(DB(D_BIT) = '1', "T15.7 D set after write");

        -- Status bits survive across reads
        read_reg(0, 3);
        check(DB(U_BIT) = '1', "T15.8 U persists across reads");
        check(DB(D_BIT) = '1', "T15.9 D persists across reads");

        idle;

        -----------------------------------------------------------------------
        -- TEST 16: CPU can overwrite MMU-set status bits
        --
        -- After MMU sets U and D, CPU clears them by writing the status
        -- register.  Verifies that CPU writes take precedence.
        -----------------------------------------------------------------------
        report "--- Test 16: CPU overwrites status bits ---";

        -- seg 0 currently has U=1, D=1 from test 15
        write_reg(0, 3, make_status('1', '0', 1));   -- clear U, D, F
        read_reg(0, 3);
        check(DB(U_BIT) = '0', "T16.1 CPU cleared U");
        check(DB(D_BIT) = '0', "T16.2 CPU cleared D");

        idle;

        -----------------------------------------------------------------------
        -- TEST 17: Segment index preserved through translations
        --
        -- The 16-bit index is CPU bookkeeping; the MMU should never
        -- modify it.
        -----------------------------------------------------------------------
        report "--- Test 17: Index field preserved ---";

        disable_all;
        load_seg(0, x"AA000000", x"00001000", MASK_2_10, make_status('1','0', 16#ABCD#));

        translate(x"00001000");       -- hit
        latch;                        -- U gets set
        translate(x"00001000", true); -- write hit
        latch;                        -- D gets set

        read_reg(0, 3);
        check(DB(15 downto 0) = x"ABCD", "T17.1 Index unchanged after translations");

        idle;

        -----------------------------------------------------------------------
        -- TEST 18: WP segment — write blocked, read still produces correct PAB
        -----------------------------------------------------------------------
        report "--- Test 18: WP read vs write ---";

        disable_all;
        load_seg(0, x"BEEF0000", x"40000000", MASK_2_16, make_status('1','1', 5));

        -- Read: PAB correct, no faults
        translate(x"40000000");
        check(SegFault  = '1', "T18.1 Hit on read");
        check(ProtFault = '1', "T18.2 No prot fault on read");
        check(PAB = calc_pab(x"40000000", x"BEEF0000", MASK_2_16),
              "T18.3 PAB correct on read");

        -- Write: ProtFault, RW_output blocked
        translate(x"40000000", true);
        check(SegFault  = '1', "T18.4 Segment still matches");
        check(ProtFault = '0', "T18.5 ProtFault on write");
        check(RW_output = '1', "T18.6 Write blocked (RW_output=read)");

        idle;

        -----------------------------------------------------------------------
        -- TEST 19: Replacing one segment while others stay active
        --
        -- Simulates the OS evicting slot 1 and loading a new descriptor.
        -----------------------------------------------------------------------
        report "--- Test 19: Segment replacement ---";

        disable_all;
        load_seg(0, x"AA000000", x"00001000", MASK_2_10, make_status('1','0', 1));
        load_seg(1, x"BB000000", x"20000000", MASK_2_20, make_status('1','0', 2));

        -- Both hit
        translate(x"00001000");
        check(SegFault = '1', "T19.1 Seg0 hit before replacement");
        translate(x"20000000");
        check(SegFault = '1', "T19.2 Seg1 hit before replacement");

        -- Evict seg 1: disable, reload with different descriptor
        disable_seg(1);
        load_seg(1, x"CC000000", x"60000000", MASK_2_16, make_status('1','0', 7));

        -- Old address misses
        translate(x"20000000");
        check(SegFault = '0', "T19.3 Old seg1 addr misses after eviction");

        -- New address hits
        translate(x"60000000");
        check(SegFault = '1', "T19.4 New seg1 addr hits");
        check(PAB = calc_pab(x"60000000", x"CC000000", MASK_2_16),
              "T19.5 New seg1 PAB correct");

        -- Seg 0 unaffected
        translate(x"00001000");
        check(SegFault = '1', "T19.6 Seg0 still works");
        check(PAB = calc_pab(x"00001000", x"AA000000", MASK_2_10),
              "T19.7 Seg0 PAB unchanged");

        idle;

        -----------------------------------------------------------------------
        -- SUMMARY
        -----------------------------------------------------------------------
        report "==============================================";
        report "  RESULTS: " & integer'image(pass_cnt) & " passed, "
                             & integer'image(fail_cnt) & " failed";
        report "==============================================";

        if fail_cnt = 0 then
            report "ALL TESTS PASSED" severity note;
        else
            report "SOME TESTS FAILED" severity failure;
        end if;

        done <= true;
        wait;
    end process;

end architecture tb;