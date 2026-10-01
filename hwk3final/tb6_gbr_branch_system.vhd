----------------------------------------------------------------------------
--  TB6_GBR_Branch_System  --  SH-2 CPU Integration Testbench 6
--
--  Tests GBR byte/word/longword ops, byte read-modify-write @(R0,GBR),
--  TAS.B, delay-slot branches (BT/S, BF/S), JMP, JSR, BSRF, VBR ops. PC
--  relative offsets will need to be adjusted when pipelining.
--
--  Instructions tested (21 checks):
--    MOV.B R0,@(disp,GBR)     MOV.B @(disp,GBR),R0
--    MOV.W R0,@(disp,GBR)     MOV.W @(disp,GBR),R0
--    MOV.L R0,@(disp,GBR)     MOV.L @(disp,GBR),R0
--    AND.B #imm,@(R0,GBR)     OR.B #imm,@(R0,GBR)
--    XOR.B #imm,@(R0,GBR)     TST.B #imm,@(R0,GBR)
--    TAS.B @Rn
--    BT/S label (taken + not taken)
--    BF/S label (taken + not taken)
--    JMP @Rm                   JSR @Rm
--    BSRF Rm
--    LDC Rm,VBR               STC VBR,Rn
--    STC.L VBR,@-Rn            LDC.L @Rm+,VBR
--
--  Disassembly (address : encoding : instruction):
--    0x0000: DE49  MOV.L @(0x49,PC),R14
--    0x0002: DF4A  MOV.L @(0x4A,PC),R15
--    0x0004: 0009  NOP
--    0x0006: D14A  MOV.L @(0x4A,PC),R1
--    0x0008: 411E  LDC R1,GBR            GBR = 0x1200
--    0x000A: E05A  MOV #0x5A,R0
--    0x000C: C000  MOV.B R0,@(0,GBR)     [0x1200] byte = 0x5A
--    0x000E: C400  MOV.B @(0,GBR),R0     R0 = sign-ext 0x5A
--    0x0010: 2E02  MOV.L R0,@R14
--    0x0012: 7E04  ADD #4,R14
--    0x0014: D047  MOV.L @(0x47,PC),R0
--    0x0016: C102  MOV.W R0,@(2*2,GBR)   [0x1204] word = 0x1234
--    0x0018: C502  MOV.W @(2*2,GBR),R0   R0 = sign-ext 0x1234
--    0x001A: 2E02  MOV.L R0,@R14
--    0x001C: 7E04  ADD #4,R14
--    0x001E: D046  MOV.L @(0x46,PC),R0
--    0x0020: C202  MOV.L R0,@(2*4,GBR)   [0x1208] = 0xCAFEBABE
--    0x0022: C602  MOV.L @(2*4,GBR),R0   R0 = 0xCAFEBABE
--    0x0024: 2E02  MOV.L R0,@R14
--    0x0026: 7E04  ADD #4,R14
--    0x0028: E010  MOV #0x10,R0           R0 = 0x10 offset
--    0x002A: E1FF  MOV #0xFF,R1
--    0x002C: D343  MOV.L @(0x43,PC),R3
--    0x002E: 2310  MOV.B R1,@R3           [0x1210] = 0xFF
--    0x0030: CD0F  AND.B #0x0F,@(R0,GBR) -> 0xFF & 0x0F = 0x0F
--    0x0032: 6230  MOV.B @R3,R2           R2 = sign-ext 0x0F
--    0x0034: 2E22  MOV.L R2,@R14
--    0x0036: 7E04  ADD #4,R14
--    0x0038: E010  MOV #0x10,R0
--    0x003A: CFA0  OR.B #0xA0,@(R0,GBR)  -> 0x0F | 0xA0 = 0xAF
--    0x003C: 6230  MOV.B @R3,R2           R2 = sign-ext 0xAF
--    0x003E: 2E22  MOV.L R2,@R14
--    0x0040: 7E04  ADD #4,R14
--    0x0042: E010  MOV #0x10,R0
--    0x0044: CEFF  XOR.B #0xFF,@(R0,GBR) -> 0xAF ^ 0xFF = 0x50
--    0x0046: 6230  MOV.B @R3,R2           R2 = sign-ext 0x50
--    0x0048: 2E22  MOV.L R2,@R14
--    0x004A: 7E04  ADD #4,R14
--    0x004C: E010  MOV #0x10,R0
--    0x004E: CC0F  TST.B #0x0F,@(R0,GBR) T = (0x50 & 0x0F == 0) = 1
--    0x0050: 0129  MOVT R1
--    0x0052: 2E12  MOV.L R1,@R14
--    0x0054: 7E04  ADD #4,R14
--    0x0056: E100  MOV #0,R1
--    0x0058: D339  MOV.L @(0x39,PC),R3
--    0x005A: 2310  MOV.B R1,@R3           [0x1214] = 0x00
--    0x005C: 431B  TAS.B @R3              T=(old==0)=1; set bit7
--    0x005E: 0129  MOVT R1                R1 = 1
--    0x0060: 2E12  MOV.L R1,@R14
--    0x0062: 7E04  ADD #4,R14
--    0x0064: 6230  MOV.B @R3,R2           R2 = sign-ext 0x80
--    0x0066: 2E22  MOV.L R2,@R14
--    0x0068: 7E04  ADD #4,R14
--    0x006A: 0018  SETT                   T = 1
--    0x006C: E109  MOV #9,R1
--    0x006E: 8D01  BT/S +1                taken
--    0x0070: 7101  ADD #1,R1              delay slot: R1 = 10
--    0x0072: E1EE  MOV #0xEE,R1           (poison - skipped)
--    0x0074: 2E12  MOV.L R1,@R14          [R14] = 10
--    0x0076: 7E04  ADD #4,R14
--    0x0078: 0008  CLRT                   T = 0
--    0x007A: E10B  MOV #11,R1
--    0x007C: 8D01  BT/S +1                not taken
--    0x007E: 0009  NOP                    delay slot
--    0x0080: 7101  ADD #1,R1              R1 = 12 (fall through)
--    0x0082: 2E12  MOV.L R1,@R14          [R14] = 12
--    0x0084: 7E04  ADD #4,R14
--    0x0086: 0008  CLRT                   T = 0
--    0x0088: E10D  MOV #13,R1
--    0x008A: 8F01  BF/S +1                taken
--    0x008C: 7101  ADD #1,R1              delay slot: R1 = 14
--    0x008E: E1EE  MOV #0xEE,R1           (poison - skipped)
--    0x0090: 2E12  MOV.L R1,@R14          [R14] = 14
--    0x0092: 7E04  ADD #4,R14
--    0x0094: 0018  SETT                   T = 1
--    0x0096: E10F  MOV #15,R1
--    0x0098: 8F01  BF/S +1                not taken
--    0x009A: 0009  NOP                    delay slot
--    0x009C: 7101  ADD #1,R1              R1 = 16 (fall through)
--    0x009E: 2E12  MOV.L R1,@R14          [R14] = 16
--    0x00A0: 7E04  ADD #4,R14
--    0x00A2: D128  MOV.L @(0x28,PC),R1
--    0x00A4: E211  MOV #17,R2
--    0x00A6: 412B  JMP @R1
--    0x00A8: 7201  ADD #1,R2              delay slot: R2 = 18
--    0x00AA: E2EE  MOV #0xEE,R2           (poison)
--    0x00AC: 2E22  MOV.L R2,@R14          [R14] = 18
--    0x00AE: 7E04  ADD #4,R14
--    0x00B0: D125  MOV.L @(0x25,PC),R1
--    0x00B2: E213  MOV #19,R2
--    0x00B4: 410B  JSR @R1                PR = PC+4
--    0x00B6: 0009  NOP                    delay slot
--    0x00B8: E214  MOV #20,R2             after RTS return
--    0x00BA: A004  BRA +4
--    0x00BC: 0009  NOP                    delay slot
--    0x00BE: 2E22  MOV.L R2,@R14          sub: store R2=19
--    0x00C0: 7E04  ADD #4,R14
--    0x00C2: 000B  RTS
--    0x00C4: 0009  NOP                    delay slot
--    0x00C6: 2E22  MOV.L R2,@R14          [R14] = 20 (return val)
--    0x00C8: 7E04  ADD #4,R14
--    0x00CA: E215  MOV #21,R2
--    0x00CC: E106  MOV #6,R1
--    0x00CE: 0103  BSRF R1                -> sub; PR = PC+4
--    0x00D0: 0009  NOP                    delay slot
--    0x00D2: E216  MOV #22,R2             after BSRF return
--    0x00D4: A004  BRA +4
--    0x00D6: 0009  NOP                    delay slot
--    0x00D8: 2E22  MOV.L R2,@R14          BSRF sub: store R2=21
--    0x00DA: 7E04  ADD #4,R14
--    0x00DC: 000B  RTS
--    0x00DE: 0009  NOP                    delay slot
--    0x00E0: 2E22  MOV.L R2,@R14          [R14] = 22 (return)
--    0x00E2: 7E04  ADD #4,R14
--    0x00E4: D119  MOV.L @(0x19,PC),R1
--    0x00E6: 412E  LDC R1,VBR             VBR = 0x00002000
--    0x00E8: 0222  STC VBR,R2             R2 = 0x00002000
--    0x00EA: 2E22  MOV.L R2,@R14
--    0x00EC: 7E04  ADD #4,R14
--    0x00EE: 4F23  STC.L VBR,@-R15        push VBR
--    0x00F0: 62F2  MOV.L @R15,R2          peek stack
--    0x00F2: 7F04  ADD #4,R15             restore SP
--    0x00F4: 2E22  MOV.L R2,@R14
--    0x00F6: 7E04  ADD #4,R14
--    0x00F8: D115  MOV.L @(0x15,PC),R1
--    0x00FA: 2F16  MOV.L R1,@-R15         push 0x3000
--    0x00FC: 63F3  MOV R15,R3
--    0x00FE: 4327  LDC.L @R3+,VBR        VBR = 0x00003000
--    0x0100: 7F04  ADD #4,R15             restore SP
--    0x0102: 0222  STC VBR,R2
--    0x0104: 2E22  MOV.L R2,@R14
--    0x0106: 7E04  ADD #4,R14
--    0x0108: AFFE  BRA .                  self-loop
--    0x010A: 0009  NOP                    delay slot
--    -- Data constants (at 0x0128) --
--    0x0128: 00001000
--    0x012C: 00001100
--    0x0130: 00001200
--    0x0134: 00001234
--    0x0138: CAFEBABE
--    0x013C: 00001210
--    0x0140: 00001214
--    0x0144: 000000AC   (JMP target)
--    0x0148: 000000BE   (JSR target)
--    0x014C: 00002000
--    0x0150: 00003000
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity TB6_GBRBranchSystem is
end entity;

architecture sim of TB6_GBRBranchSystem is

    constant CLK_PERIOD : time    := 20 ns;
    constant PROG_HEX   : string  := "tb6_program.hex";
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

        check(x"00001000", x"0000005A", "MOV.B @(disp,GBR) roundtrip");
        check(x"00001004", x"00001234", "MOV.W @(disp,GBR) roundtrip");
        check(x"00001008", x"CAFEBABE", "MOV.L @(disp,GBR) roundtrip");
        check(x"0000100C", x"0000000F", "AND.B #imm,@(R0,GBR)");
        check(x"00001010", x"FFFFFFAF", "OR.B #imm,@(R0,GBR)");
        check(x"00001014", x"00000050", "XOR.B #imm,@(R0,GBR)");
        check(x"00001018", x"00000001", "TST.B #imm,@(R0,GBR)");
        check(x"0000101C", x"00000001", "TAS.B @Rn (T result)");
        check(x"00001020", x"FFFFFF80", "TAS.B @Rn (byte got bit7)");
        check(x"00001024", x"0000000A", "BT/S taken + delay slot");
        check(x"00001028", x"0000000C", "BT/S not taken");
        check(x"0000102C", x"0000000E", "BF/S taken + delay slot");
        check(x"00001030", x"00000010", "BF/S not taken");
        check(x"00001034", x"00000012", "JMP @Rm + delay slot");
        check(x"00001038", x"00000013", "JSR @Rm (sub body ran)");
        check(x"0000103C", x"00000014", "JSR+RTS (return reached)");
        check(x"00001040", x"00000015", "BSRF Rm (sub body)");
        check(x"00001044", x"00000016", "BSRF+RTS (return reached)");
        check(x"00001048", x"00002000", "LDC Rm,VBR + STC VBR,Rn");
        check(x"0000104C", x"00002000", "STC.L VBR,@-Rn");
        check(x"00001050", x"00003000", "LDC.L @Rm+,VBR");

        ---------------------------------------------------------------
        -- SUMMARY
        ---------------------------------------------------------------
        report "TB6: PASSED=" & integer'image(pass_cnt)
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
