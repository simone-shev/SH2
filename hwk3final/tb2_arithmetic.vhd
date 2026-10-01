----------------------------------------------------------------------------
--  TB2_Arithmetic  --  SH-2 CPU Integration Testbench 2
--
--  Two phases controlled by a single signal "loading":
--    loading='1' : TB owns the bus (load hex, then check memory)
--                  CPU is held in reset so it tri-states all its outputs
--    loading='0' : CPU owns the bus (program execution)
--                  TB drives 'Z' so it doesn't interfere
--
--  CPU, memory, and TB all share the same resolved bus signals.
--  Only one non-Z driver is active at any given time.
--
--  Instructions covered:
--    ADD Rm,Rn    ADD #imm,Rn   SUB Rm,Rn
--    ADDC (two cases: no carry-out, carry-out)
--    ADDV (overflow)    NEG    NEGC
--    DT (decrement-and-test loop x3)
--    CMP/EQ  CMP/HS  CMP/GT  CMP/PZ   SUBV (underflow)
--    MOVT   CLRT
--
--  Expected results in data memory (block 1):
--   0x1000  0x00000008   ADD 5+3=8
--   0x1004  0x00000002   ADD #-3 -> 2
--   0x1008  0x00000007   SUB 10-3=7
--   0x100C  0xFFFFFFFF   ADDC no carry: 0xFFFFFFFE+1+T=0
--   0x1010  0x00000000   ADDC carry: result=0
--   0x1014  0x00000001   ADDC carry: T=1 stored
--   0x1018  0x80000000   ADDV overflow result
--   0x101C  0xFFFFFFFB   NEG 5
--   0x1020  0xFFFFFFFF   NEGC 0-1-0
--   0x1024  0x00000001   DT: T=1 when count=0
--   0x1028  0x00000001   CMP/EQ 42==42: T=1
--   0x102C  0x00000001   CMP/HS 10>=5 unsigned: T=1
--   0x1030  0x00000001   CMP/GT 6>5 signed: T=1
--   0x1034  0x00000001   CMP/PZ 0>=0: T=1
--   0x1038  0x7FFFFFFF   SUBV 0x80000000-1 underflow
--
--  Program image (assembled; 44 words = 176 bytes):
--
--  Disassembly (address : encoding : instruction):
--  -- Setup --
--    0x0000: DE28  MOV.L @(0x28,PC),R14    R14 = 0x00001000
--    0x0002: 0009  NOP
--  -- Test 1: ADD Rm,Rn --
--    0x0004: E105  MOV #5,R1
--    0x0006: E203  MOV #3,R2
--    0x0008: 321C  ADD R1,R2               R2 = 5+3 = 8
--    0x000A: 2E22  MOV.L R2,@R14           [0x1000] = 0x00000008
--    0x000C: 7E04  ADD #4,R14
--  -- Test 2: ADD #imm --
--    0x000E: E105  MOV #5,R1
--    0x0010: 71FD  ADD #-3,R1              R1 = 5-3 = 2
--    0x0012: 2E12  MOV.L R1,@R14           [0x1004] = 0x00000002
--    0x0014: 7E04  ADD #4,R14
--  -- Test 3: SUB Rm,Rn --
--    0x0016: E10A  MOV #10,R1
--    0x0018: E203  MOV #3,R2
--    0x001A: 3128  SUB R2,R1               R1 = 10-3 = 7
--    0x001C: 2E12  MOV.L R1,@R14           [0x1008] = 0x00000007
--    0x001E: 7E04  ADD #4,R14
--  -- Test 4: ADDC no carry --
--    0x0020: E101  MOV #1,R1
--    0x0022: 6117  NOT R1,R1               R1 = 0xFFFFFFFE
--    0x0024: E201  MOV #1,R2
--    0x0026: 312E  ADDC R2,R1              R1 = 0xFFFFFFFE+1+T(0) = 0xFFFFFFFF, C=0
--    0x0028: 2E12  MOV.L R1,@R14           [0x100C] = 0xFFFFFFFF
--    0x002A: 7E04  ADD #4,R14
--  -- Test 5: ADDC with carry --
--    0x002C: E100  MOV #0,R1
--    0x002E: 6117  NOT R1,R1               R1 = 0xFFFFFFFF
--    0x0030: E201  MOV #1,R2
--    0x0032: 312E  ADDC R2,R1              R1 = 0xFFFFFFFF+1+T(0) = 0, C=1
--    0x0034: 2E12  MOV.L R1,@R14           [0x1010] = 0x00000000
--    0x0036: 7E04  ADD #4,R14
--  -- Test 6: MOVT (T=1 from carry) --
--    0x0038: 0329  MOVT R3                 R3 = T = 1
--    0x003A: 2E32  MOV.L R3,@R14           [0x1014] = 0x00000001
--    0x003C: 7E04  ADD #4,R14
--  -- Test 7: ADDV overflow --
--    0x003E: D11A  MOV.L @(0x1A,PC),R1     R1 = 0x7FFFFFFF
--    0x0040: E201  MOV #1,R2
--    0x0042: 312F  ADDV R2,R1              R1 = 0x7FFFFFFF+1 = 0x80000000, V=1
--    0x0044: 2E12  MOV.L R1,@R14           [0x1018] = 0x80000000
--    0x0046: 7E04  ADD #4,R14
--  -- Test 8: NEG --
--    0x0048: E105  MOV #5,R1
--    0x004A: 621B  NEG R1,R2               R2 = -5 = 0xFFFFFFFB
--    0x004C: 2E22  MOV.L R2,@R14           [0x101C] = 0xFFFFFFFB
--    0x004E: 7E04  ADD #4,R14
--  -- Test 9: NEGC --
--    0x0050: 0008  CLRT                    T = 0
--    0x0052: E101  MOV #1,R1
--    0x0054: 621A  NEGC R1,R2              R2 = 0-1-T(0) = 0xFFFFFFFF
--    0x0056: 2E22  MOV.L R2,@R14           [0x1020] = 0xFFFFFFFF
--    0x0058: 7E04  ADD #4,R14
--  -- Test 10: DT loop --
--    0x005A: E103  MOV #3,R1
--    0x005C: 4110  DT R1                   R1 = R1-1, T = (R1==0)
--    0x005E: 8BFD  BF -1                   loop to 0x005C if T=0
--    0x0060: 0329  MOVT R3                 R3 = T = 1
--    0x0062: 2E32  MOV.L R3,@R14           [0x1024] = 0x00000001
--    0x0064: 7E04  ADD #4,R14
--  -- Test 11: CMP/EQ --
--    0x0066: E12A  MOV #42,R1
--    0x0068: E22A  MOV #42,R2
--    0x006A: 3120  CMP/EQ R2,R1            T = (42==42) = 1
--    0x006C: 0329  MOVT R3                 R3 = 1
--    0x006E: 2E32  MOV.L R3,@R14           [0x1028] = 0x00000001
--    0x0070: 7E04  ADD #4,R14
--  -- Test 12: CMP/HS --
--    0x0072: E10A  MOV #10,R1
--    0x0074: E205  MOV #5,R2
--    0x0076: 3122  CMP/HS R2,R1            T = (10>=5 unsigned) = 1
--    0x0078: 0329  MOVT R3                 R3 = 1
--    0x007A: 2E32  MOV.L R3,@R14           [0x102C] = 0x00000001
--    0x007C: 7E04  ADD #4,R14
--  -- Test 13: CMP/GT --
--    0x007E: E106  MOV #6,R1
--    0x0080: E205  MOV #5,R2
--    0x0082: 3127  CMP/GT R2,R1            T = (6>5 signed) = 1
--    0x0084: 0329  MOVT R3                 R3 = 1
--    0x0086: 2E32  MOV.L R3,@R14           [0x1030] = 0x00000001
--    0x0088: 7E04  ADD #4,R14
--  -- Test 14: CMP/PZ --
--    0x008A: E100  MOV #0,R1
--    0x008C: 4111  CMP/PZ R1               T = (0>=0) = 1
--    0x008E: 0329  MOVT R3                 R3 = 1
--    0x0090: 2E32  MOV.L R3,@R14           [0x1034] = 0x00000001
--    0x0092: 7E04  ADD #4,R14
--  -- Test 15: SUBV underflow --
--    0x0094: D105  MOV.L @(0x05,PC),R1     R1 = 0x80000000
--    0x0096: E201  MOV #1,R2
--    0x0098: 312B  SUBV R2,R1              R1 = 0x80000000-1 = 0x7FFFFFFF, V=1
--    0x009A: 2E12  MOV.L R1,@R14           [0x1038] = 0x7FFFFFFF
--    0x009C: A000  BRA .                   self-loop
--    0x009E: 0009  NOP                     (delay slot)
--    0x00A0: 0009  NOP
--    0x00A2: 0009  NOP
--    -- Data constants --
--    0x00A4: 00001000
--    0x00A8: 7FFFFFFF
--    0x00AC: 80000000
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity TB2_Arithmetic is
end entity;

architecture sim of TB2_Arithmetic is

    constant CLK_PERIOD : time    := 20 ns;
    constant PROG_HEX   : string  := "tb2_program.hex";
    constant MEM_WORDS  : integer := 256;

    signal clk     : std_logic := '0';
    signal reset   : std_logic := '0';
    signal loading : std_logic := '1';

    -- Shared bus — CPU, memory, and TB all connect here
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

        for i in 1 to 300 loop
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

        check(x"00001000", x"00000008", "ADD Rm,Rn: 5+3=8");
        check(x"00001004", x"00000002", "ADD #imm: 5+(-3)=2");
        check(x"00001008", x"00000007", "SUB Rm,Rn: 10-3=7");
        check(x"0000100C", x"FFFFFFFF", "ADDC no carry: 0xFFFFFFFE+1");
        check(x"00001010", x"00000000", "ADDC carry: result=0");
        check(x"00001014", x"00000001", "ADDC carry: T=1 stored");
        check(x"00001018", x"80000000", "ADDV overflow result");
        check(x"0000101C", x"FFFFFFFB", "NEG 5 = 0xFFFFFFFB");
        check(x"00001020", x"FFFFFFFF", "NEGC 0-1-0 = 0xFFFFFFFF");
        check(x"00001024", x"00000001", "DT: T=1 after count=0");
        check(x"00001028", x"00000001", "CMP/EQ 42==42: T=1");
        check(x"0000102C", x"00000001", "CMP/HS 10>=5 unsigned: T=1");
        check(x"00001030", x"00000001", "CMP/GT 6>5 signed: T=1");
        check(x"00001034", x"00000001", "CMP/PZ 0>=0: T=1");
        check(x"00001038", x"7FFFFFFF", "SUBV 0x80000000-1 underflow");

        ---------------------------------------------------------------
        -- SUMMARY
        ---------------------------------------------------------------
        report "TB2: PASSED=" & integer'image(pass_cnt)
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
