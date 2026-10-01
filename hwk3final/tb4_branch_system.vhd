----------------------------------------------------------------------------
--  TB4_BranchSystem  –  SH-2 CPU Integration Testbench 4
--
--  Two phases controlled by a single signal "loading":
--    loading='1' : TB owns the bus (load hex, then check memory)
--                  CPU is held in reset so it tri-states all its outputs
--    loading='0' : CPU owns the bus (program execution)
--                  TB drives 'Z' so it doesn't interfere
--
--  CPU, memory, and TB all share the same resolved bus signals.
--  Only one non-Z driver is active at any given time. PC relative offsets 
--  will need to be changed when pipelining. 
--
--  Instructions covered (coherent real-program narrative):
--
--    BRA label              – delayed unconditional branch; delay slot verified
--    BSR label / RTS        – delayed subroutine call and return
--    BT  label (taken)      – branch when T=1
--    BT  label (not taken)  – no branch when T=0; fall-through verified
--    BF  label (taken)      – branch when T=0
--    BF  label (not taken)  – no branch when T=1; fall-through verified
--    BRAF Rm                – delayed far branch (PC-relative via register)
--    LDC Rm,GBR             – load GBR from register
--    STC GBR,Rn             – store GBR to register
--    LDS Rm,PR / STS PR,Rn  – PR roundtrip
--    CLRT / SETT            – T-bit manipulation (precondition for BT/BF)
--    STC SR,Rn              – read SR; T=0 bit verified
--    STC.L GBR,@-Rn         – push GBR onto stack
--    LDC.L @Rm+,GBR         – pop GBR from stack
--    STS.L PR,@-Rn          – push PR onto stack
--    LDS.L @Rm+,PR          – pop PR from stack
--    MOV.L @(disp,PC),Rn   – constant loading
--    MOV.L Rm,@Rn / ADD#4  – result store / pointer advance
--    NOP                    – delay slot filler
--
--  Methodology:
--    Each test section stores a unique "breadcrumb" value at the next
--    result slot in the data area.  Wrong control flow writes the wrong
--    value (or skips the write entirely), which the check phase detects.
--    Delay-slot execution is verified by having the slot instruction
--    increment R13; the incremented value is then stored and checked.
--
--  Expected results in data memory (block 1):
--
--   0x1000  0x00000001   BRA destination reached
--   0x1004  0x00000001   BRA delay slot verified (R13=1, MOVT)
--   0x1008  0x00000002   BT taken (T=1)
--   0x100C  0x00000003   BT not-taken fall-through (T=0)
--   0x1010  0x00000004   BF taken (T=0)
--   0x1014  0x00000005   BF not-taken fall-through (T=1)
--   0x1018  0x00000006   BRAF destination reached
--   0x101C  0x00000003   BSR subroutine body
--   0x1020  0x00000004   RTS: returned to caller
--   0x1024  0x00001200   LDC/STC GBR roundtrip
--   0x1028  0xDEADC0DE   LDS/STS PR roundtrip
--   0x102C  SR value     STC SR: T bit (bit 0) = 0 after CLRT
--   0x1030  0x00001200   STC.L/LDC.L GBR stack roundtrip
--   0x1034  0xDEADC0DE   STS.L/LDS.L PR stack roundtrip
--
--  Program image (assembled; 49 words = 196 bytes):
--
--  Disassembly (address : encoding : instruction):
--  -- Setup --
--    0x0000: DE2C  MOV.L @(44,PC),R14   R14 = 0x00001000
--    0x0002: 0009  NOP
--    0x0004: DF2C  MOV.L @(44,PC),R15   R15 = 0x000011F0
--    0x0006: ED00  MOV #0,R13           R13 = 0
--  -- T4-1: BRA + delay slot --
--    0x0008: A000  BRA +0               -> 0x000C
--    0x000A: 7D01  ADD #1,R13           [delay slot]
--    0x000C: E101  MOV #1,R1
--    0x000E: 2E12  MOV.L R1,@R14        [0x1000] = 1
--    0x0010: 7E04  ADD #4,R14
--    0x0012: E201  MOV #1,R2
--    0x0014: 3D20  CMP/EQ R2,R13        T=1 if delay ran
--    0x0016: 0329  MOVT R3
--    0x0018: 2E32  MOV.L R3,@R14        [0x1004] = 1
--    0x001A: 7E04  ADD #4,R14
--  -- T4-2: BT taken (T=1) --
--    0x001C: 0018  SETT
--    0x001E: E102  MOV #2,R1
--    0x0020: 8901  BT +1                -> 0x0026 (taken)
--    0x0022: E1EE  MOV #0xEE,R1         (poison)
--    0x0024: 0009  NOP
--    0x0026: 2E12  MOV.L R1,@R14        [0x1008] = 2
--    0x0028: 7E04  ADD #4,R14
--  -- T4-3: BT not-taken (T=0) --
--    0x002A: 0008  CLRT
--    0x002C: E103  MOV #3,R1
--    0x002E: 8901  BT +1                -> 0x0034 (not taken)
--    0x0030: 2E12  MOV.L R1,@R14        [0x100C] = 3
--    0x0032: 7E04  ADD #4,R14
--  -- T4-4: BF taken (T=0) --
--    0x0034: 0008  CLRT
--    0x0036: E104  MOV #4,R1
--    0x0038: 8B01  BF +1                -> 0x003E (taken)
--    0x003A: E1DD  MOV #0xDD,R1         (poison)
--    0x003C: 0009  NOP
--    0x003E: 2E12  MOV.L R1,@R14        [0x1010] = 4
--    0x0040: 7E04  ADD #4,R14
--  -- T4-5: BF not-taken (T=1) --
--    0x0042: 0018  SETT
--    0x0044: E105  MOV #5,R1
--    0x0046: 8B01  BF +1                -> 0x004C (not taken)
--    0x0048: 2E12  MOV.L R1,@R14        [0x1014] = 5
--    0x004A: 7E04  ADD #4,R14
--  -- T4-6: BRAF --
--    0x004C: E104  MOV #4,R1            offset = 4
--    0x004E: E206  MOV #6,R2
--    0x0050: 0123  BRAF R1              -> 0x0058
--    0x0052: 0009  NOP                  [delay slot]
--    0x0054: E2BB  MOV #0xBB,R2         (poison)
--    0x0056: 0009  NOP
--    0x0058: 2E22  MOV.L R2,@R14        [0x1018] = 6
--    0x005A: 7E04  ADD #4,R14
--  -- T4-7: BSR + RTS --
--    0x005C: B005  BSR +5               -> 0x006A (subroutine)
--    0x005E: 0009  NOP                  [delay slot]
--    0x0060: E104  MOV #4,R1            (return point)
--    0x0062: 2E12  MOV.L R1,@R14        [0x1020] = 4
--    0x0064: 7E04  ADD #4,R14
--    0x0066: A005  BRA +5               -> 0x0074 (skip sub)
--    0x0068: 0009  NOP                  [delay slot]
--    -- subroutine --
--    0x006A: E103  MOV #3,R1
--    0x006C: 2E12  MOV.L R1,@R14        [0x101C] = 3
--    0x006E: 7E04  ADD #4,R14
--    0x0070: 000B  RTS
--    0x0072: 0009  NOP                  [delay slot]
--  -- T4-8: LDC/STC GBR --
--    0x0074: D111  MOV.L @(17,PC),R1    R1 = 0x1200
--    0x0076: 411E  LDC R1,GBR
--    0x0078: 0212  STC GBR,R2
--    0x007A: 2E22  MOV.L R2,@R14        [0x1024] = 0x1200
--    0x007C: 7E04  ADD #4,R14
--  -- T4-9: LDS/STS PR --
--    0x007E: D110  MOV.L @(16,PC),R1    R1 = 0xDEADCODE
--    0x0080: 412A  LDS R1,PR
--    0x0082: 022A  STS PR,R2
--    0x0084: 2E22  MOV.L R2,@R14        [0x1028] = 0xDEADC0DE
--    0x0086: 7E04  ADD #4,R14
--  -- T4-10: CLRT + STC SR --
--    0x0088: 0008  CLRT
--    0x008A: 0102  STC SR,R1
--    0x008C: 2E12  MOV.L R1,@R14        [0x102C] = SR (T=0)
--    0x008E: 7E04  ADD #4,R14
--  -- T4-11: STC.L/LDC.L GBR stack roundtrip --
--    0x0090: 4F13  STC.L GBR,@-R15
--    0x0092: E100  MOV #0,R1
--    0x0094: 411E  LDC R1,GBR           (clear GBR)
--    0x0096: 4F17  LDC.L @R15+,GBR
--    0x0098: 0112  STC GBR,R1
--    0x009A: 2E12  MOV.L R1,@R14        [0x1030] = 0x1200
--    0x009C: 7E04  ADD #4,R14
--  -- T4-12: STS.L/LDS.L PR stack roundtrip --
--    0x009E: D108  MOV.L @(8,PC),R1     R1 = 0xDEADC0DE
--    0x00A0: 412A  LDS R1,PR
--    0x00A2: 4F22  STS.L PR,@-R15
--    0x00A4: E100  MOV #0,R1
--    0x00A6: 412A  LDS R1,PR            (clear PR)
--    0x00A8: 4F26  LDS.L @R15+,PR
--    0x00AA: 012A  STS PR,R1
--    0x00AC: 2E12  MOV.L R1,@R14        [0x1034] = 0xDEADC0DE
--    0x00AE: 7E04  ADD #4,R14
--  -- End --
--    0x00B0: AFFE  BRA .                self-loop
--    0x00B2: 0009  NOP
--  -- Constant pool --
--    0x00B4: 00001000                   data_base
--    0x00B8: 000011F0                   stack_base
--    0x00BC: 00001200                   gbr_val
--    0x00C0: DEADC0DE                   pr_magic
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity TB4_BranchSystem is
end entity;

architecture sim of TB4_BranchSystem is

    constant CLK_PERIOD : time    := 20 ns;
    constant PROG_HEX   : string  := "tb4_program.hex";
    constant MEM_WORDS  : integer := 256;

    signal clk     : std_logic := '0';
    signal reset   : std_logic := '0';
    signal loading : std_logic := '1';

    -- Shared bus -- CPU, memory, and TB all connect here
    signal AB  : std_logic_vector(31 downto 0);
    signal DB  : std_logic_vector(31 downto 0);
    signal RE0, RE1, RE2, RE3 : std_logic;
    signal WE0, WE1, WE2, WE3 : std_logic;

    -- TB-side bus signals
    signal tb_AB : std_logic_vector(31 downto 0) := (others => '0');
    signal tb_DB : std_logic_vector(31 downto 0) := (others => '0');
    signal tb_RE : std_logic := '1';
    signal tb_WE : std_logic := '1';

begin

    clk <= not clk after CLK_PERIOD / 2;

    -- TB bus mux: drives bus when loading='1', releases ('Z') when loading='0'
    -- During loading='0' the CPU drives the bus instead (via its port map)
    AB  <= tb_AB when loading = '1' else (others => 'Z');
    DB  <= tb_DB when (loading = '1' and tb_WE = '0') else (others => 'Z');
    RE0 <= tb_RE when loading = '1' else 'Z';
    RE1 <= tb_RE when loading = '1' else 'Z';
    RE2 <= tb_RE when loading = '1' else 'Z';
    RE3 <= tb_RE when loading = '1' else 'Z';
    WE0 <= tb_WE when loading = '1' else 'Z';
    WE1 <= tb_WE when loading = '1' else 'Z';
    WE2 <= tb_WE when loading = '1' else 'Z';
    WE3 <= tb_WE when loading = '1' else 'Z';

    -- CPU connects directly to the shared bus
    dut : entity work.SH2_CPU
        port map (
            Reset => reset,  NMI => '1',  INT => '1',  clock => clk,
            AB  => AB,   DB  => DB,
            RE0 => RE0,  RE1 => RE1,  RE2 => RE2,  RE3 => RE3,
            WE0 => WE0,  WE1 => WE1,  WE2 => WE2,  WE3 => WE3
        );

    mem : entity work.MEMORY32x32
        generic map (
            MEMSIZE     => MEM_WORDS,
            START_ADDR0 => 16#00000000#,
            START_ADDR1 => 16#00001000#,
            START_ADDR2 => 16#10000000#,
            START_ADDR3 => 16#20000000#
        )
        port map (
            RE0 => RE0,  RE1 => RE1,  RE2 => RE2,  RE3 => RE3,
            WE0 => WE0,  WE1 => WE1,  WE2 => WE2,  WE3 => WE3,
            MemAB => AB,  MemDB => DB
        );

    stim : process
        file     hex_file : text;
        variable fstatus  : file_open_status;
        variable l        : line;
        variable word     : std_logic_vector(31 downto 0);
        variable addr     : unsigned(31 downto 0);
        variable pass_cnt : integer := 0;
        variable fail_cnt : integer := 0;

        procedure check(a   : std_logic_vector(31 downto 0);
                        exp : std_logic_vector(31 downto 0);
                        tag : string) is
        begin
            tb_AB <= a;
            tb_RE <= '0';
            tb_WE <= '1';
            wait for CLK_PERIOD;
            if DB = exp then
                pass_cnt := pass_cnt + 1;
                report "PASS: " & tag severity note;
            else
                fail_cnt := fail_cnt + 1;
                report "FAIL: " & tag
                     & "  got=0x" & to_hstring(DB)
                     & "  exp=0x" & to_hstring(exp) severity error;
            end if;
            tb_RE <= '1';
            wait for CLK_PERIOD;
        end procedure;

        procedure check_tbit_zero(a   : std_logic_vector(31 downto 0);
                                  tag : string) is
        begin
            tb_AB <= a;
            tb_RE <= '0';
            tb_WE <= '1';
            wait for CLK_PERIOD;
            if DB(0) = '0' then
                pass_cnt := pass_cnt + 1;
                report "PASS: " & tag severity note;
            else
                fail_cnt := fail_cnt + 1;
                report "FAIL: " & tag
                     & "  SR=0x" & to_hstring(DB)
                     & "  bit[0]=T expected 0, got 1" severity error;
            end if;
            tb_RE <= '1';
            wait for CLK_PERIOD;
        end procedure;

    begin
        ---------------------------------------------------------------
        -- LOAD PHASE
        ---------------------------------------------------------------
        loading <= '1';
        reset   <= '0';
        tb_RE   <= '1';
        tb_WE   <= '1';
        wait for CLK_PERIOD * 2;

        file_open(fstatus, hex_file, PROG_HEX, read_mode);
        assert fstatus = open_ok
            report "Cannot open " & PROG_HEX severity failure;

        addr := (others => '0');
        while not endfile(hex_file) loop
            readline(hex_file, l);
            if l'length > 0 then
                hread(l, word);
                tb_AB <= std_logic_vector(addr);
                tb_DB <= word;
                tb_WE <= '0';
                wait for CLK_PERIOD;
                tb_WE <= '1';
                wait for CLK_PERIOD;
                addr := addr + 4;
            end if;
        end loop;
        file_close(hex_file);

        ---------------------------------------------------------------
        -- CPU PHASE
        ---------------------------------------------------------------
        wait until rising_edge(clk);
        loading <= '0';
        reset   <= '1';

        wait for CLK_PERIOD * 2;

        for i in 1 to 600 loop
            wait until rising_edge(clk);
        end loop;

        ---------------------------------------------------------------
        -- CHECK PHASE
        ---------------------------------------------------------------
        wait until rising_edge(clk);
        reset   <= '0';
        loading <= '1';
        tb_RE   <= '1';
        tb_WE   <= '1';
        wait for CLK_PERIOD * 2;

        check(x"00001000", x"00000001", "BRA destination reached");
        check(x"00001004", x"00000001", "BRA delay slot ran (R13=1)");
        check(x"00001008", x"00000002", "BT taken (T=1)");
        check(x"0000100C", x"00000003", "BT not-taken fall-through (T=0)");
        check(x"00001010", x"00000004", "BF taken (T=0)");
        check(x"00001014", x"00000005", "BF not-taken fall-through (T=1)");
        check(x"00001018", x"00000006", "BRAF destination reached");
        check(x"0000101C", x"00000003", "BSR subroutine body");
        check(x"00001020", x"00000004", "RTS: returned to caller");
        check(x"00001024", x"00001200", "LDC/STC GBR roundtrip");
        check(x"00001028", x"DEADC0DE", "LDS/STS PR roundtrip");
        check_tbit_zero(x"0000102C",    "STC SR: T=0 after CLRT");
        check(x"00001030", x"00001200", "STC.L/LDC.L GBR stack roundtrip");
        check(x"00001034", x"DEADC0DE", "STS.L/LDS.L PR stack roundtrip");

        ---------------------------------------------------------------
        -- SUMMARY
        ---------------------------------------------------------------
        report "TB4: PASSED=" & integer'image(pass_cnt)
             & "  FAILED=" & integer'image(fail_cnt) severity note;
        if fail_cnt = 0 then
            report "*** ALL TESTS PASSED ***" severity note;
        else
            assert false
                report integer'image(fail_cnt) & " TEST(S) FAILED"
                severity failure;
        end if;
        wait;
    end process;

end architecture;
