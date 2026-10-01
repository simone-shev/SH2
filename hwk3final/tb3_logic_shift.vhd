----------------------------------------------------------------------------
--  TB3_LogicShift  --  SH-2 CPU Integration Testbench 3
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
--    AND Rm,Rn   OR Rm,Rn   XOR Rm,Rn   NOT Rm,Rn   TST Rm,Rn
--    AND #imm,R0   OR #imm,R0
--    SHLL  SHLR   SHLL16  SHLR16
--    SHAL  SHAR   ROTL    ROTCL  ROTCR
--    CLRT  MOVT
--
--  Expected results in data memory (block 1):
--   0x1000  0x00000000   AND F0F0&0F0F=0
--   0x1004  0xFFFFFFFF   OR  F0F0|0F0F=FFFF
--   0x1008  0xFFFFFFFF   XOR AAAA^5555=FFFF
--   0x100C  0x55555555   NOT ~0xAAAAAAAA
--   0x1010  0x00000001   TST zero result -> T=1
--   0x1014  0x0000000F   AND#imm 0xFF & 0x0F
--   0x1018  0x000000A5   OR#imm 0x00 | 0xA5
--   0x101C  0x00000002   SHLL 0x80000001
--   0x1020  0x00000001   T after SHLL
--   0x1024  0x40000000   SHLR 0x80000001
--   0x1028  0x00000001   T after SHLR
--   0x102C  0xABCD0000   SHLL16 0x0000ABCD
--   0x1030  0x0000ABCD   SHLR16 result
--   0x1034  0x80000002   SHAL 0x40000001
--   0x1038  0x00000000   T after SHAL (MSB was 0)
--   0x103C  0xC0000001   SHAR 0x80000002
--   0x1040  0x00000003   ROTL 0x80000001
--   0x1044  0x00000001   T after ROTL
--   0x1048  0x55555554   ROTCL 0xAAAAAAAA T=0
--   0x104C  0x00000001   T after ROTCL
--   0x1050  0xAAAAAAAA   ROTCR 0x55555554 T=1
--   0x1054  0x00000000   T after ROTCR
--
--  Program image (assembled; 53 words = 212 bytes):
--
--  Disassembly (address : encoding : instruction):
--  -- Setup --
--    0x0000: DE2C  MOV.L @(0x2C,PC),R14    R14 = 0x00001000
--    0x0002: 0009  NOP
--  -- Test 1: AND Rm,Rn --
--    0x0004: D12C  MOV.L @(0x2C,PC),R1     R1 = 0xF0F0F0F0
--    0x0006: D22D  MOV.L @(0x2D,PC),R2     R2 = 0x0F0F0F0F
--    0x0008: 2219  AND R1,R2               R2 = 0x00000000
--    0x000A: 2E22  MOV.L R2,@R14           [0x1000] = 0x00000000
--    0x000C: 7E04  ADD #4,R14
--  -- Test 2: OR Rm,Rn --
--    0x000E: D12A  MOV.L @(0x2A,PC),R1     R1 = 0xF0F0F0F0
--    0x0010: D22A  MOV.L @(0x2A,PC),R2     R2 = 0x0F0F0F0F
--    0x0012: 221B  OR R1,R2                R2 = 0xFFFFFFFF
--    0x0014: 2E22  MOV.L R2,@R14           [0x1004] = 0xFFFFFFFF
--    0x0016: 7E04  ADD #4,R14
--  -- Test 3: XOR Rm,Rn --
--    0x0018: D129  MOV.L @(0x29,PC),R1     R1 = 0xAAAAAAAA
--    0x001A: D22A  MOV.L @(0x2A,PC),R2     R2 = 0x55555555
--    0x001C: 221A  XOR R1,R2               R2 = 0xFFFFFFFF
--    0x001E: 2E22  MOV.L R2,@R14           [0x1008] = 0xFFFFFFFF
--    0x0020: 7E04  ADD #4,R14
--  -- Test 4: NOT --
--    0x0022: D127  MOV.L @(0x27,PC),R1     R1 = 0xAAAAAAAA
--    0x0024: 6217  NOT R1,R2               R2 = 0x55555555
--    0x0026: 2E22  MOV.L R2,@R14           [0x100C] = 0x55555555
--    0x0028: 7E04  ADD #4,R14
--  -- Test 5: TST --
--    0x002A: D123  MOV.L @(0x23,PC),R1     R1 = 0xF0F0F0F0
--    0x002C: D223  MOV.L @(0x23,PC),R2     R2 = 0x0F0F0F0F
--    0x002E: 2128  TST R2,R1               T = (R1 & R2 == 0) = 1
--    0x0030: 0329  MOVT R3                 R3 = T = 1
--    0x0032: 2E32  MOV.L R3,@R14           [0x1010] = 0x00000001
--    0x0034: 7E04  ADD #4,R14
--  -- Test 6: AND #imm,R0 --
--    0x0036: E0FF  MOV #-1,R0              R0 = 0xFFFFFFFF
--    0x0038: C90F  AND #0x0F,R0            R0 = 0x0000000F
--    0x003A: 2E02  MOV.L R0,@R14           [0x1014] = 0x0000000F
--    0x003C: 7E04  ADD #4,R14
--  -- Test 7: OR #imm,R0 --
--    0x003E: E000  MOV #0,R0               R0 = 0x00000000
--    0x0040: CBA5  OR #0xA5,R0             R0 = 0x000000A5
--    0x0042: 2E02  MOV.L R0,@R14           [0x1018] = 0x000000A5
--    0x0044: 7E04  ADD #4,R14
--  -- Test 8: SHLL --
--    0x0046: D120  MOV.L @(0x20,PC),R1     R1 = 0x80000001
--    0x0048: 4100  SHLL R1                 R1 = 0x00000002, T = 1
--    0x004A: 2E12  MOV.L R1,@R14           [0x101C] = 0x00000002
--    0x004C: 7E04  ADD #4,R14
--  -- Test 9: T after SHLL --
--    0x004E: 0329  MOVT R3                 R3 = T = 1
--    0x0050: 2E32  MOV.L R3,@R14           [0x1020] = 0x00000001
--    0x0052: 7E04  ADD #4,R14
--  -- Test 10: SHLR --
--    0x0054: D11C  MOV.L @(0x1C,PC),R1     R1 = 0x80000001
--    0x0056: 4101  SHLR R1                 R1 = 0x40000000, T = 1
--    0x0058: 2E12  MOV.L R1,@R14           [0x1024] = 0x40000000
--    0x005A: 7E04  ADD #4,R14
--  -- Test 11: T after SHLR --
--    0x005C: 0329  MOVT R3                 R3 = T = 1
--    0x005E: 2E32  MOV.L R3,@R14           [0x1028] = 0x00000001
--    0x0060: 7E04  ADD #4,R14
--  -- Test 12: SHLL16 --
--    0x0062: D11A  MOV.L @(0x1A,PC),R1     R1 = 0x0000ABCD
--    0x0064: 4128  SHLL16 R1               R1 = 0xABCD0000
--    0x0066: 2E12  MOV.L R1,@R14           [0x102C] = 0xABCD0000
--    0x0068: 7E04  ADD #4,R14
--  -- Test 13: SHLR16 --
--    0x006A: 4129  SHLR16 R1               R1 = 0x0000ABCD
--    0x006C: 2E12  MOV.L R1,@R14           [0x1030] = 0x0000ABCD
--    0x006E: 7E04  ADD #4,R14
--  -- Test 14: SHAL --
--    0x0070: D117  MOV.L @(0x17,PC),R1     R1 = 0x40000001
--    0x0072: 4120  SHAL R1                 R1 = 0x80000002, T = 0
--    0x0074: 2E12  MOV.L R1,@R14           [0x1034] = 0x80000002
--    0x0076: 7E04  ADD #4,R14
--  -- Test 15: T after SHAL --
--    0x0078: 0329  MOVT R3                 R3 = T = 0
--    0x007A: 2E32  MOV.L R3,@R14           [0x1038] = 0x00000000
--    0x007C: 7E04  ADD #4,R14
--  -- Test 16: SHAR --
--    0x007E: 4121  SHAR R1                 R1 = 0xC0000001, T = 0
--    0x0080: 2E12  MOV.L R1,@R14           [0x103C] = 0xC0000001
--    0x0082: 7E04  ADD #4,R14
--  -- Test 17: ROTL --
--    0x0084: D110  MOV.L @(0x10,PC),R1     R1 = 0x80000001
--    0x0086: 4104  ROTL R1                 R1 = 0x00000003, T = 1
--    0x0088: 2E12  MOV.L R1,@R14           [0x1040] = 0x00000003
--    0x008A: 7E04  ADD #4,R14
--  -- Test 18: T after ROTL --
--    0x008C: 0329  MOVT R3                 R3 = T = 1
--    0x008E: 2E32  MOV.L R3,@R14           [0x1044] = 0x00000001
--    0x0090: 7E04  ADD #4,R14
--  -- Test 19: ROTCL --
--    0x0092: 0008  CLRT                    T = 0
--    0x0094: D10A  MOV.L @(0x0A,PC),R1     R1 = 0xAAAAAAAA
--    0x0096: 4124  ROTCL R1                R1 = 0x55555554, T = 1
--    0x0098: 2E12  MOV.L R1,@R14           [0x1048] = 0x55555554
--    0x009A: 7E04  ADD #4,R14
--  -- Test 20: T after ROTCL --
--    0x009C: 0329  MOVT R3                 R3 = T = 1
--    0x009E: 2E32  MOV.L R3,@R14           [0x104C] = 0x00000001
--    0x00A0: 7E04  ADD #4,R14
--  -- Test 21: ROTCR --
--    0x00A2: 4125  ROTCR R1                R1 = 0xAAAAAAAA, T = 0
--    0x00A4: 2E12  MOV.L R1,@R14           [0x1050] = 0xAAAAAAAA
--    0x00A6: 7E04  ADD #4,R14
--  -- Test 22: T after ROTCR --
--    0x00A8: 0329  MOVT R3                 R3 = T = 0
--    0x00AA: 2E32  MOV.L R3,@R14           [0x1054] = 0x00000000
--    0x00AC: 7E04  ADD #4,R14
--  -- End --
--    0x00AE: AFFE  BRA .                   self-loop
--    0x00B0: 0009  NOP
--    0x00B2: 0009  NOP
--    -- Data constants --
--    0x00B4: 00001000
--    0x00B8: F0F0F0F0
--    0x00BC: 0F0F0F0F
--    0x00C0: AAAAAAAA
--    0x00C4: 55555555
--    0x00C8: 80000001
--    0x00CC: 0000ABCD
--    0x00D0: 40000001
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity TB3_LogicShift is
end entity;

architecture sim of TB3_LogicShift is

    constant CLK_PERIOD : time    := 20 ns;
    constant PROG_HEX   : string  := "tb3_program.hex";
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

        for i in 1 to 500 loop
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

        check(x"00001000", x"00000000", "AND F0F0&0F0F=0");
        check(x"00001004", x"FFFFFFFF", "OR  F0F0|0F0F=FFFF");
        check(x"00001008", x"FFFFFFFF", "XOR AAAA^5555=FFFF");
        check(x"0000100C", x"55555555", "NOT ~0xAAAAAAAA");
        check(x"00001010", x"00000001", "TST zero result -> T=1");
        check(x"00001014", x"0000000F", "AND#imm upper24 cleared");
        check(x"00001018", x"000000A5", "OR#imm 0x00|0xA5");
        check(x"0000101C", x"00000002", "SHLL 0x80000001");
        check(x"00001020", x"00000001", "T after SHLL");
        check(x"00001024", x"40000000", "SHLR 0x80000001");
        check(x"00001028", x"00000001", "T after SHLR");
        check(x"0000102C", x"ABCD0000", "SHLL16 0x0000ABCD");
        check(x"00001030", x"0000ABCD", "SHLR16 result");
        check(x"00001034", x"80000002", "SHAL 0x40000001");
        check(x"00001038", x"00000000", "T after SHAL (MSB=0)");
        check(x"0000103C", x"C0000001", "SHAR 0x80000002");
        check(x"00001040", x"00000003", "ROTL 0x80000001");
        check(x"00001044", x"00000001", "T after ROTL");
        check(x"00001048", x"55555554", "ROTCL 0xAAAAAAAA T=0");
        check(x"0000104C", x"00000001", "T after ROTCL");
        check(x"00001050", x"AAAAAAAA", "ROTCR 0x55555554 T=1");
        check(x"00001054", x"00000000", "T after ROTCR");

        ---------------------------------------------------------------
        -- SUMMARY
        ---------------------------------------------------------------
        report "TB3: PASSED=" & integer'image(pass_cnt)
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
