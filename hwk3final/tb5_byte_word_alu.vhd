----------------------------------------------------------------------------
--  TB5_ByteWordALU  --  SH-2 CPU Integration Testbench 5
--
--  Tests remaining byte/word data transfers, compares, EXTU.B, SUBC,
--  XOR #imm, TST #imm, MOVA, and remaining multi-bit shifts. PC relative offsets 
--  will need to be adjusted when pipelining.
--
--  Instructions tested (26 checks):
--    MOV.W @(disp,PC),Rn       MOV.B Rm,@Rn + MOV.B @Rm,Rn
--    MOV.W Rm,@Rn + MOV.W @Rm,Rn
--    MOV.B @Rm+,Rn             MOV.W @Rm+,Rn
--    MOV.B Rm,@-Rn             MOV.W Rm,@-Rn
--    MOV.B R0,@(disp,Rn)      MOV.B @(disp,Rm),R0
--    MOV.W R0,@(disp,Rn)      MOV.W @(disp,Rm),R0
--    MOV.B Rm,@(R0,Rn)        MOV.B @(R0,Rm),Rn
--    MOV.W Rm,@(R0,Rn)        MOV.W @(R0,Rm),Rn
--    MOVA @(disp,PC),R0
--    CMP/EQ #imm,R0            CMP/GE Rm,Rn
--    CMP/HI Rm,Rn              CMP/PL Rn
--    CMP/STR Rm,Rn             EXTU.B Rm,Rn
--    SUBC Rm,Rn                XOR #imm,R0
--    TST #imm,R0               ROTR Rn
--    SHLL2 Rn     SHLL8 Rn     SHLR2 Rn     SHLR8 Rn
--
--  Disassembly (address : encoding : instruction):
--    0x0000: DE44  MOV.L @(0x44,PC),R14
--    0x0002: DF45  MOV.L @(0x45,PC),R15
--    0x0004: 0009  NOP
--    0x0006: 9189  MOV.W @(0x89,PC),R1     R1 = 0x00001234
--    0x0008: 2E12  MOV.L R1,@R14
--    0x000A: 7E04  ADD #4,R14
--    0x000C: E142  MOV #0x42,R1
--    0x000E: 2E10  MOV.B R1,@R14          [R14] byte = 0x42
--    0x0010: 62E0  MOV.B @R14,R2          R2 = sign-ext 0x42 = 0x00000042
--    0x0012: 2E22  MOV.L R2,@R14          [R14] = 0x00000042
--    0x0014: 7E04  ADD #4,R14
--    0x0016: D141  MOV.L @(0x41,PC),R1
--    0x0018: 2E11  MOV.W R1,@R14          [R14] word = 0x1234
--    0x001A: 62E1  MOV.W @R14,R2          R2 = sign-ext 0x1234 = 0x00001234
--    0x001C: 2E22  MOV.L R2,@R14          [R14] = 0x00001234
--    0x001E: 7E04  ADD #4,R14
--    0x0020: E1AB  MOV #0xAB,R1           R1 = 0xFFFFFFAB (sign-ext)
--    0x0022: 2E10  MOV.B R1,@R14          [R14] byte = 0xAB
--    0x0024: 63E3  MOV R14,R3             R3 = R14 (save ptr)
--    0x0026: 6234  MOV.B @R3+,R2          R2 = sign-ext 0xAB = 0xFFFFFFAB
--    0x0028: 2E22  MOV.L R2,@R14          [R14] = 0xFFFFFFAB
--    0x002A: 7E04  ADD #4,R14
--    0x002C: D13C  MOV.L @(0x3C,PC),R1
--    0x002E: 2E11  MOV.W R1,@R14          [R14] word = 0x8765
--    0x0030: 63E3  MOV R14,R3
--    0x0032: 6235  MOV.W @R3+,R2          R2 = sign-ext 0x8765 = 0xFFFF8765
--    0x0034: 2E22  MOV.L R2,@R14          [R14] = 0xFFFF8765
--    0x0036: 7E04  ADD #4,R14
--    0x0038: E155  MOV #0x55,R1
--    0x003A: 63E3  MOV R14,R3             R3 = R14
--    0x003C: 7304  ADD #4,R3              R3 = R14+4
--    0x003E: 2314  MOV.B R1,@-R3          [R3-1] byte = 0x55; R3 = R3-1
--    0x0040: 6230  MOV.B @R3,R2           R2 = sign-ext 0x55 = 0x00000055
--    0x0042: 2E22  MOV.L R2,@R14          [R14] = 0x00000055
--    0x0044: 7E04  ADD #4,R14
--    0x0046: D137  MOV.L @(0x37,PC),R1
--    0x0048: 63E3  MOV R14,R3
--    0x004A: 7304  ADD #4,R3
--    0x004C: 2315  MOV.W R1,@-R3         [R3-2] word = 0x5678; R3 -= 2
--    0x004E: 6231  MOV.W @R3,R2           R2 = sign-ext 0x5678 = 0x00005678
--    0x0050: 2E22  MOV.L R2,@R14          [R14] = 0x00005678
--    0x0052: 7E04  ADD #4,R14
--    0x0054: E037  MOV #0x37,R0
--    0x0056: 80E3  MOV.B R0,@(3,R14)     [R14+3] byte = 0x37
--    0x0058: 84E3  MOV.B @(3,R14),R0     R0 = sign-ext 0x37 = 0x00000037
--    0x005A: 2E02  MOV.L R0,@R14          [R14] = 0x00000037
--    0x005C: 7E04  ADD #4,R14
--    0x005E: D02F  MOV.L @(0x2F,PC),R0
--    0x0060: 81E1  MOV.W R0,@(1*2,R14)   [R14+2] word = 0x1234
--    0x0062: 85E1  MOV.W @(1*2,R14),R0   R0 = sign-ext 0x1234 = 0x00001234
--    0x0064: 2E02  MOV.L R0,@R14          [R14] = 0x00001234
--    0x0066: 7E04  ADD #4,R14
--    0x0068: E002  MOV #2,R0              R0 = 2 (offset)
--    0x006A: E17E  MOV #0x7E,R1
--    0x006C: 0E14  MOV.B R1,@(R0,R14)    [R14+2] byte = 0x7E
--    0x006E: 02EC  MOV.B @(R0,R14),R2    R2 = sign-ext 0x7E = 0x0000007E
--    0x0070: 2E22  MOV.L R2,@R14          [R14] = 0x0000007E
--    0x0072: 7E04  ADD #4,R14
--    0x0074: E002  MOV #2,R0              R0 = 2
--    0x0076: D12C  MOV.L @(0x2C,PC),R1
--    0x0078: 0E15  MOV.W R1,@(R0,R14)    [R14+2] word = 0x2345
--    0x007A: 02ED  MOV.W @(R0,R14),R2    R2 = sign-ext 0x2345 = 0x00002345
--    0x007C: 2E22  MOV.L R2,@R14          [R14] = 0x00002345
--    0x007E: 7E04  ADD #4,R14
--    0x0080: C72A  MOVA @(0x2A,PC),R0      R0 = 0x0000012C
--    0x0082: 2E02  MOV.L R0,@R14          store MOVA result
--    0x0084: 7E04  ADD #4,R14
--    0x0086: E02A  MOV #42,R0
--    0x0088: 882A  CMP/EQ #42,R0          T = (42==42) = 1
--    0x008A: 0129  MOVT R1
--    0x008C: 2E12  MOV.L R1,@R14          [R14] = 1
--    0x008E: 7E04  ADD #4,R14
--    0x0090: E105  MOV #5,R1
--    0x0092: E205  MOV #5,R2
--    0x0094: 3123  CMP/GE R2,R1           T = (5>=5 signed) = 1
--    0x0096: 0329  MOVT R3
--    0x0098: 2E32  MOV.L R3,@R14          [R14] = 1
--    0x009A: 7E04  ADD #4,R14
--    0x009C: E10A  MOV #10,R1
--    0x009E: E205  MOV #5,R2
--    0x00A0: 3126  CMP/HI R2,R1           T = (10>5 unsigned) = 1
--    0x00A2: 0329  MOVT R3
--    0x00A4: 2E32  MOV.L R3,@R14          [R14] = 1
--    0x00A6: 7E04  ADD #4,R14
--    0x00A8: E101  MOV #1,R1
--    0x00AA: 4115  CMP/PL R1               T = (1>0) = 1
--    0x00AC: 0329  MOVT R3
--    0x00AE: 2E32  MOV.L R3,@R14          [R14] = 1
--    0x00B0: 7E04  ADD #4,R14
--    0x00B2: D11E  MOV.L @(0x1E,PC),R1
--    0x00B4: D21E  MOV.L @(0x1E,PC),R2
--    0x00B6: 212C  CMP/STR R2,R1          T = 1 (byte 1 matches: 0x34)
--    0x00B8: 0329  MOVT R3
--    0x00BA: 2E32  MOV.L R3,@R14          [R14] = 1
--    0x00BC: 7E04  ADD #4,R14
--    0x00BE: E1FF  MOV #0xFF,R1           R1 = 0xFFFFFFFF
--    0x00C0: 621C  EXTU.B R1,R2           R2 = 0x000000FF
--    0x00C2: 2E22  MOV.L R2,@R14          [R14] = 0x000000FF
--    0x00C4: 7E04  ADD #4,R14
--    0x00C6: 0008  CLRT                   T = 0
--    0x00C8: E10A  MOV #10,R1
--    0x00CA: E203  MOV #3,R2
--    0x00CC: 312A  SUBC R2,R1             R1 = 10-3-T(0) = 7
--    0x00CE: 2E12  MOV.L R1,@R14          [R14] = 0x00000007
--    0x00D0: 7E04  ADD #4,R14
--    0x00D2: E0FF  MOV #0xFF,R0           R0 = 0xFFFFFFFF
--    0x00D4: CA0F  XOR #0x0F,R0           R0 = 0xFFFFFFF0
--    0x00D6: 2E02  MOV.L R0,@R14          [R14] = 0xFFFFFFF0
--    0x00D8: 7E04  ADD #4,R14
--    0x00DA: E0F0  MOV #0xF0,R0           R0 = 0xFFFFFFF0
--    0x00DC: C80F  TST #0x0F,R0           T = (0xFFFFFFF0 & 0x0F == 0) = 1
--    0x00DE: 0129  MOVT R1
--    0x00E0: 2E12  MOV.L R1,@R14          [R14] = 1
--    0x00E2: 7E04  ADD #4,R14
--    0x00E4: D113  MOV.L @(0x13,PC),R1
--    0x00E6: 4105  ROTR R1                R1 = 0xC0000000, T = 1
--    0x00E8: 2E12  MOV.L R1,@R14          [R14] = 0xC0000000
--    0x00EA: 7E04  ADD #4,R14
--    0x00EC: E101  MOV #1,R1
--    0x00EE: 4108  SHLL2 R1               R1 = 4
--    0x00F0: 2E12  MOV.L R1,@R14          [R14] = 0x00000004
--    0x00F2: 7E04  ADD #4,R14
--    0x00F4: E101  MOV #1,R1
--    0x00F6: 4118  SHLL8 R1               R1 = 0x100
--    0x00F8: 2E12  MOV.L R1,@R14          [R14] = 0x00000100
--    0x00FA: 7E04  ADD #4,R14
--    0x00FC: E110  MOV #16,R1
--    0x00FE: 4109  SHLR2 R1               R1 = 4
--    0x0100: 2E12  MOV.L R1,@R14          [R14] = 0x00000004
--    0x0102: 7E04  ADD #4,R14
--    0x0104: D10C  MOV.L @(0x0C,PC),R1
--    0x0106: 4119  SHLR8 R1               R1 = 0xFF
--    0x0108: 2E12  MOV.L R1,@R14          [R14] = 0x000000FF
--    0x010A: 7E04  ADD #4,R14
--    0x010C: AFFE  BRA .                  self-loop
--    0x010E: 0009  NOP                    (delay slot)
--    0x0110: 0009  NOP
--    0x0112: 0009  NOP                    (padding)
--    -- Data constants (at 0x0114) --
--    0x0114: 00001000
--    0x0118: 00001100
--    0x011C: 00001234
--    0x0120: FFFF8765
--    0x0124: 00005678
--    0x0128: 00002345
--    0x012C: 12345678
--    0x0130: AB34CDEF
--    0x0134: 80000001
--    0x0138: 0000FF00
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity TB5_ByteWordALU is
end entity;

architecture sim of TB5_ByteWordALU is

    constant CLK_PERIOD : time    := 20 ns;
    constant PROG_HEX   : string  := "tb5_program.hex";
    constant MEM_WORDS  : integer := 256;

    signal clk     : std_logic := '0';
    signal reset   : std_logic := '0';
    signal loading : std_logic := '1';

    -- Shared bus
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

        for i in 1 to 400 loop
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

        check(x"00001000", x"00001234", "MOV.W @(disp,PC)");
        check(x"00001004", x"00000042", "MOV.B Rm,@Rn + MOV.B @Rm,Rn");
        check(x"00001008", x"00001234", "MOV.W Rm,@Rn + MOV.W @Rm,Rn");
        check(x"0000100C", x"FFFFFFAB", "MOV.B @Rm+,Rn");
        check(x"00001010", x"FFFF8765", "MOV.W @Rm+,Rn");
        check(x"00001014", x"00000055", "MOV.B Rm,@-Rn");
        check(x"00001018", x"00005678", "MOV.W Rm,@-Rn");
        check(x"0000101C", x"00000037", "MOV.B R0,@(disp,Rn) + MOV.B @(disp,Rm),R0");
        check(x"00001020", x"00001234", "MOV.W R0,@(disp,Rn) + MOV.W @(disp,Rm),R0");
        check(x"00001024", x"0000007E", "MOV.B Rm,@(R0,Rn) + MOV.B @(R0,Rm),Rn");
        check(x"00001028", x"00002345", "MOV.W Rm,@(R0,Rn) + MOV.W @(R0,Rm),Rn");
        check(x"0000102C", x"0000012C", "MOVA @(disp,PC),R0");
        check(x"00001030", x"00000001", "CMP/EQ #imm,R0");
        check(x"00001034", x"00000001", "CMP/GE Rm,Rn");
        check(x"00001038", x"00000001", "CMP/HI Rm,Rn");
        check(x"0000103C", x"00000001", "CMP/PL Rn");
        check(x"00001040", x"00000001", "CMP/STR Rm,Rn");
        check(x"00001044", x"000000FF", "EXTU.B Rm,Rn");
        check(x"00001048", x"00000007", "SUBC Rm,Rn");
        check(x"0000104C", x"FFFFFFF0", "XOR #imm,R0");
        check(x"00001050", x"00000001", "TST #imm,R0");
        check(x"00001054", x"C0000000", "ROTR Rn");
        check(x"00001058", x"00000004", "SHLL2 Rn");
        check(x"0000105C", x"00000100", "SHLL8 Rn");
        check(x"00001060", x"00000004", "SHLR2 Rn");
        check(x"00001064", x"000000FF", "SHLR8 Rn");

        ---------------------------------------------------------------
        -- SUMMARY
        ---------------------------------------------------------------
        report "TB5: PASSED=" & integer'image(pass_cnt)
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
