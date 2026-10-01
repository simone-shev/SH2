----------------------------------------------------------------------------
--  TB1_DataTransfer  --  SH-2 CPU Integration Testbench 1
--
--  Two phases controlled by a single signal "loading":
--    loading='1' : TB owns the bus (load hex, then check memory)
--                  CPU is held in reset so it tri-states all its outputs
--    loading='0' : CPU owns the bus (program execution)
--                  TB drives 'Z' so it doesn't interfere
--
--  CPU, memory, and TB all share the same resolved bus signals.
--  Only one non-Z driver is active at any given time. PC relative offsets 
--  will need to be adjusted when pipelining.
--
--  Program image (assembled; 37 words = 148 bytes):
--
--  Disassembly (address : encoding : instruction):
--    0x0000: DE1D  MOV.L @(0x1D,PC),R14    R14 = 0x00001000
--    0x0002: DF1E  MOV.L @(0x1E,PC),R15    R15 = 0x000011F0
--    0x0004: D11E  MOV.L @(0x1E,PC),R1     R1 = 0xDEADBEEF
--    0x0006: 2E12  MOV.L R1,@R14           [0x1000] = 0xDEADBEEF
--    0x0008: 62E2  MOV.L @R14,R2           R2 = 0xDEADBEEF
--    0x000A: 7E04  ADD #4,R14              R14 = 0x1004
--    0x000C: D11D  MOV.L @(0x1D,PC),R1     R1 = 0xAABBCCDD
--    0x000E: 6318  SWAP.B R1,R3            R3 = 0xAABBDDCC
--    0x0010: 2E32  MOV.L R3,@R14           [0x1004] = 0xAABBDDCC
--    0x0012: 7E04  ADD #4,R14
--    0x0014: 6419  SWAP.W R1,R4            R4 = 0xCCDDAABB
--    0x0016: 2E42  MOV.L R4,@R14           [0x1008] = 0xCCDDAABB
--    0x0018: 7E04  ADD #4,R14
--    0x001A: 651E  EXTS.B R1,R5            R5 = 0xFFFFFFDD
--    0x001C: 2E52  MOV.L R5,@R14           [0x100C] = 0xFFFFFFDD
--    0x001E: 7E04  ADD #4,R14
--    0x0020: 661D  EXTU.W R1,R6            R6 = 0x0000CCDD
--    0x0022: 2E62  MOV.L R6,@R14           [0x1010] = 0x0000CCDD
--    0x0024: 7E04  ADD #4,R14
--    0x0026: D118  MOV.L @(0x18,PC),R1     R1 = 0x12345678
--    0x0028: D218  MOV.L @(0x18,PC),R2     R2 = 0xABCDEF00
--    0x002A: 221D  XTRCT R1,R2             R2 = 0x5678ABCD
--    0x002C: 2E22  MOV.L R2,@R14           [0x1014] = 0x5678ABCD
--    0x002E: 7E04  ADD #4,R14
--    0x0030: D117  MOV.L @(0x17,PC),R1     R1 = 0xC0DE1234
--    0x0032: 1E10  MOV.L R1,@(0,R14)       [0x1018] = 0xC0DE1234
--    0x0034: 53E0  MOV.L @(0,R14),R3       R3 = 0xC0DE1234
--    0x0036: 2E32  MOV.L R3,@R14           [0x1018] confirmed
--    0x0038: 7E04  ADD #4,R14
--    0x003A: E008  MOV #8,R0               R0 = 8
--    0x003C: D110  MOV.L @(0x10,PC),R1     R1 = 0xDEADBEEF
--    0x003E: 0E16  MOV.L R1,@(R0,R14)      [0x1024] = 0xDEADBEEF
--    0x0040: 02EE  MOV.L @(R0,R14),R2      R2 = 0xDEADBEEF
--    0x0042: 2E22  MOV.L R2,@R14           [0x101C] = 0xDEADBEEF
--    0x0044: 7E04  ADD #4,R14
--    0x0046: 0018  SETT
--    0x0048: 0129  MOVT R1                 R1 = 1
--    0x004A: 2E12  MOV.L R1,@R14           [0x1020] = 0x00000001
--    0x004C: 7E04  ADD #4,R14
--    0x004E: D10D  MOV.L @(0x0D,PC),R1     R1 = 0xAABBCCDD
--    0x0050: 2F16  MOV.L R1,@-R15          push 0xAABBCCDD
--    0x0052: 62F6  MOV.L @R15+,R2          pop R2 = 0xAABBCCDD
--    0x0054: 2E22  MOV.L R2,@R14           [0x1024] = 0xAABBCCDD
--    0x0056: 7E04  ADD #4,R14
--    0x0058: E103  MOV #3,R1
--    0x005A: E204  MOV #4,R2
--    0x005C: 312C  ADD R2,R1               R1 = 7
--    0x005E: E307  MOV #7,R3
--    0x0060: 3130  CMP/EQ R3,R1            T = 1 (7 == 7)
--    0x0062: 8900  BT +0                   skip to 0x0066 (T=1)
--    0x0064: E1FF  MOV #-1,R1              (skipped)
--    0x0066: 2E12  MOV.L R1,@R14           [0x1028] = 7
--    0x0068: 7E04  ADD #4,R14
--    0x006A: D106  MOV.L @(0x06,PC),R1     R1 = 0xAABBCCDD
--    0x006C: 621F  EXTS.W R1,R2            R2 = 0xFFFFCCDD
--    0x006E: 2E22  MOV.L R2,@R14           [0x102C] = 0xFFFFCCDD
--    0x0070: 7E04  ADD #4,R14
--    0x0072: AFFE  BRA .                   self-loop (disp=-2)
--    0x0074: 0009  NOP                     (delay slot)
--    0x0076: 0009  NOP
--    -- Data constants --
--    0x0078: 00001000
--    0x007C: 000011F0
--    0x0080: DEADBEEF
--    0x0084: AABBCCDD
--    0x0088: 12345678
--    0x008C: ABCDEF00
--    0x0090: C0DE1234
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity TB1_DataTransfer is
end entity;

architecture sim of TB1_DataTransfer is

    constant CLK_PERIOD : time    := 20 ns;
    constant PROG_HEX   : string  := "tb1_program.hex";
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

        wait for CLK_PERIOD * 2; -- hold reset for a couple cycles to ensure CPU is fully reset and tri-stating its outputs

        for i in 1 to 300 loop
            wait until rising_edge(clk);
            --wait for 0 ns;
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

        check(x"00001000", x"DEADBEEF", "MOV.L @Rm roundtrip");
        check(x"00001004", x"AABBDDCC", "SWAP.B");
        check(x"00001008", x"CCDDAABB", "SWAP.W");
        check(x"0000100C", x"FFFFFFDD", "EXTS.B");
        check(x"00001010", x"0000CCDD", "EXTU.W");
        check(x"00001014", x"5678ABCD", "XTRCT");
        check(x"00001018", x"C0DE1234", "MOV.L @(disp,Rn) roundtrip");
        check(x"0000101C", x"DEADBEEF", "MOV.L @(R0,Rn) indexed");
        check(x"00001020", x"00000001", "MOVT after SETT");
        check(x"00001024", x"AABBCCDD", "pre-dec/post-inc roundtrip");
        check(x"00001028", x"00000007", "ADD+CMP/EQ+BT");
        check(x"0000102C", x"FFFFCCDD", "EXTS.W");

        ---------------------------------------------------------------
        -- SUMMARY
        ---------------------------------------------------------------
        report "TB1: PASSED=" & integer'image(pass_cnt)
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
