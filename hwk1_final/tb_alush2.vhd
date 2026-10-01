--------------------------------------------------------------------------------
-- tb_ALUSH2.vhd
-- Comprehensive testbench for the SH2 ALU (ALUSH2 entity)
--
-- Tests are organised by SH2 instruction group.  Each group sets control
-- signals to match the decoder output for that instruction, then checks
-- res and t_bit against the SH2 programming manual specification.
--
-- *** CONFIRMED ASSUMPTIONS ***
--   F-Block encoding  : F(A,B) = (f3·A·B)|(f2·A·~B)|(f1·~A·B)|(f0·~A·~B)
--     AND="1000"  OR="1110"  XOR="0110"
--     NOT_A="0011"  NOT_B="0101"
--     PASS_A="1100"  PASS_B="1010"
--   res_sel           : 0=ALU  1=ShiftN (shift_sel: 0=×2 1=×8 2=×16)
--                       2=SwapB  3=Extend  4=Xtrct
--   ADDER             : computes opa + F(opa,opb) + cin_adjusted
--     (F-block output drives the adder B-side)
--
-- *** CARRY / BORROW CONVENTION (SUBC / NEGC) ***
--   SH2 specifies T=1 when a borrow occurs.  The adder computes
--   opa + NOT(opb) + NOT(T_in) for these instructions, so the raw
--   arithmetic carry_out = 1 means NO borrow (ARM / PowerPC sense).
--   Expected T values in the SUBC and NEGC groups are written per the
--   SH2 specification (T=1 on borrow). 
--
-- *** NOT TESTED (not yet implemented) ***
--   MUL, MULS, MULU, DMULS, DMULU, MAC, MAC.W, MAC.L
--
-- Simulation finish: look for the "=== SUMMARY ===" report line.

-- Revision history:    
--   10 Apr 26  Claude Code    Initial version
--   15 Apr 26  Claude Code    Added tests for shift results, swap, extend, extract
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ALUConstants.all;
use work.TConstants.all;

entity tb_ALUSH2 is
end entity tb_ALUSH2;

architecture Behavioral of tb_ALUSH2 is

    ---------------------------------------------------------------------------
    -- DUT ports
    ---------------------------------------------------------------------------
    signal alu_opa  : std_logic_vector(31 downto 0) := (others => '0');
    signal alu_opb  : std_logic_vector(31 downto 0) := (others => '0');
    signal c_in     : std_logic                      := '0';
    signal f_cmd    : std_logic_vector( 3 downto 0)  := (others => '0');
    signal c_in_cmd : std_logic_vector( 1 downto 0)  := CinCmd_ZERO;
    signal s_cmd    : std_logic_vector( 2 downto 0)  := SCmd_LSL;
    signal alu_cmd    : std_logic_vector( 1 downto 0)  := ALUCmd_FBLOCK;
    signal shift_sel  : integer range 2 downto 0       := 0;
    signal extend_sel : std_logic_vector( 1 downto 0)  := "00";
    signal res_sel    : integer range 4 downto 0        := 0;
    signal t_sel      : std_logic_vector( 3 downto 0)  := TCmd_HOLD;
    signal res      : std_logic_vector(31 downto 0);
    signal t_bit    : std_logic;

    ---------------------------------------------------------------------------
    -- F-block command constants (bit-select encoding, confirmed above)
    ---------------------------------------------------------------------------
    constant FCmd_ZERO  : std_logic_vector(3 downto 0) := "0000"; -- 0
    constant FCmd_AND   : std_logic_vector(3 downto 0) := "1000"; -- A AND B
    constant FCmd_OR    : std_logic_vector(3 downto 0) := "1110"; -- A OR  B
    constant FCmd_XOR   : std_logic_vector(3 downto 0) := "0110"; -- A XOR B
    constant FCmd_NOTA  : std_logic_vector(3 downto 0) := "0011"; -- NOT A
    constant FCmd_NOTB  : std_logic_vector(3 downto 0) := "0101"; -- NOT B  (adder B for subtract)
    constant FCmd_PASSA : std_logic_vector(3 downto 0) := "1100"; -- pass A
    constant FCmd_PASSB : std_logic_vector(3 downto 0) := "1010"; -- pass B (adder B for add)
    constant FCmd_ONE   : std_logic_vector(3 downto 0) := "1111"; -- 1

    ---------------------------------------------------------------------------
    -- res_sel routing constants
    ---------------------------------------------------------------------------
    constant ResSel_ALU     : integer := 0;
    constant ResSel_ShiftN  : integer := 1;
    constant ResSel_Shift2  : integer := 1;  -- shift_sel=0; kept for existing tests
    constant ResSel_Shift8  : integer := 1;  -- shift_sel=1; kept for existing tests
    constant ResSel_Shift16 : integer := 1;  -- shift_sel=2; kept for existing tests
    constant ResSel_SwapB   : integer := 2;
    constant ResSel_Extend  : integer := 3;
    constant ResSel_Xtrct   : integer := 4;

    ---------------------------------------------------------------------------
    -- Combinational settling time TODO: timing okay? 
    ---------------------------------------------------------------------------
    constant TPROP : time := 20 ns;

    ---------------------------------------------------------------------------
    -- Test statistics — VHDL-2008 requires shared variables to be a
    -- protected type.
    ---------------------------------------------------------------------------
    type t_counter is protected
        procedure increment;
        impure function get return integer;
    end protected t_counter;

    type t_counter is protected body
        variable val : integer := 0;
        procedure increment is
        begin
            val := val + 1;
        end procedure;
        impure function get return integer is
        begin
            return val;
        end function;
    end protected body t_counter;

    shared variable n_tests : t_counter;
    shared variable n_fail  : t_counter;

begin

    ---------------------------------------------------------------------------
    -- DUT
    ---------------------------------------------------------------------------
    UUT : entity work.ALUSH2
        port map (
            alu_opa  => alu_opa,
            alu_opb  => alu_opb,
            c_in     => c_in,
            f_cmd    => f_cmd,
            c_in_cmd => c_in_cmd,
            s_cmd    => s_cmd,
            alu_cmd    => alu_cmd,
            shift_sel  => shift_sel,
            extend_sel => extend_sel,
            res_sel    => res_sel,
            t_sel      => t_sel,
            res      => res,
            t_bit    => t_bit
        );

    ---------------------------------------------------------------------------
    -- Stimulus
    ---------------------------------------------------------------------------
    stim : process

        -----------------------------------------------------------------------
        -- check_res : wait for propagation then assert result (and T-bit).
        --   tag      : test label shown in messages
        --   exp_res  : expected 32-bit result
        --   exp_t    : expected T-bit value
        --   chk_t    : when false, T-bit is not checked (instruction holds T)
        -----------------------------------------------------------------------
        procedure check_res(
            tag     : in string;
            exp_res : in std_logic_vector(31 downto 0);
            exp_t   : in std_logic;
            chk_t   : in boolean := true
        ) is
            variable ok : boolean := true;
        begin
            wait for TPROP;
            n_tests.increment;

            if res /= exp_res then
                report "[FAIL] " & tag
                     & "  res="     & to_hstring(res)
                     & "  exp_res=" & to_hstring(exp_res)
                     severity error;
                ok := false;
                n_fail.increment;
            end if;

            if chk_t and (t_bit /= exp_t) then
                report "[FAIL] " & tag & " T"
                     & "  t_bit=" & std_logic'image(t_bit)
                     & "  exp_t=" & std_logic'image(exp_t)
                     severity error;
                ok := false;
                n_fail.increment;
            end if;

            if ok then
                report "[PASS] " & tag severity note;
            end if;
        end procedure;

    begin

        -----------------------------------------------------------------------
        -- Safe reset
        -----------------------------------------------------------------------
        alu_opa    <= (others => '0');
        alu_opb    <= (others => '0');
        c_in       <= '0';
        f_cmd      <= FCmd_PASSA;
        c_in_cmd   <= CinCmd_ZERO;
        s_cmd      <= SCmd_LSL;
        alu_cmd    <= ALUCmd_FBLOCK;
        shift_sel  <= 0;
        extend_sel <= "00";
        res_sel    <= ResSel_ALU;
        t_sel      <= TCmd_ZERO;
        wait for TPROP;

        -----------------------------------------------------------------------
        --  ADD  Rn+Rm->Rn  T unchanged
        --  f=PASSB  cin=ZERO  alu=ADDER  t=HOLD
        -----------------------------------------------------------------------
        report ">>> ADD" severity note;
        f_cmd    <= FCmd_PASSB;
        c_in_cmd <= CinCmd_ZERO;
        alu_cmd  <= ALUCmd_ADDER;
        res_sel  <= ResSel_ALU;
        t_sel    <= TCmd_HOLD;

        report "Tbit " & std_logic'image(t_bit);
        alu_opa <= x"00000005"; alu_opb <= x"00000003"; c_in <= '0';
        check_res("ADD  5+3=8",           x"00000008", '0', false);
        alu_opa <= x"00000000"; alu_opb <= x"00000000";
        check_res("ADD  0+0=0",           x"00000000", '0', false);
        alu_opa <= x"12345678"; alu_opb <= x"00000000";
        check_res("ADD  x+0=x",           x"12345678", '0', false);
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"00000001";   -- unsigned wrap
        check_res("ADD  wrap=0",          x"00000000", '0', false);
        alu_opa <= x"7FFFFFFF"; alu_opb <= x"00000001";   -- signed +ovf
        check_res("ADD  +ovf",            x"80000000", '0', false);
        alu_opa <= x"80000000"; alu_opb <= x"FFFFFFFF";   -- signed -ovf
        check_res("ADD  -ovf",            x"7FFFFFFF", '0', false);
        alu_opa <= x"7FFFFFFF"; alu_opb <= x"7FFFFFFF";
        check_res("ADD  max+max",         x"FFFFFFFE", '0', false);
        alu_opa <= x"FFFFFFF0"; alu_opb <= x"FFFFFFF0";   -- -16 + -16 = -32
        check_res("ADD  neg+neg=-32",     x"FFFFFFE0", '0', false);
        -- T is held even when carry would set it
        c_in <= '1';
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"00000001";
        wait for TPROP;
        report "Tbit after " & std_logic'image(t_bit);
        n_tests.increment;
        if t_bit /= '0' then
            report "[FAIL] ADD  T held=0" severity error; n_fail.increment;
        else
            report "[PASS] ADD  T held=0" severity note;
        end if;
        c_in <= '0';

        -----------------------------------------------------------------------
        --  ADDC  Rn+Rm+T->Rn  Carry->T
        --  f=PASSB  cin=CIN  alu=ADDER  t=C
        -----------------------------------------------------------------------
        report ">>> ADDC" severity note;
        c_in_cmd <= CinCmd_CIN;
        t_sel    <= TCmd_C;

        alu_opa <= x"00000005"; alu_opb <= x"00000003"; c_in <= '0';
        check_res("ADDC 5+3+T0=8 C0",    x"00000008", '0');
        alu_opa <= x"00000005"; alu_opb <= x"00000003"; c_in <= '1';
        check_res("ADDC 5+3+T1=9 C0",    x"00000009", '0');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"00000001"; c_in <= '0';
        check_res("ADDC FF+1+T0=0 C1",   x"00000000", '1');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"00000000"; c_in <= '1';
        check_res("ADDC FF+0+T1=0 C1",   x"00000000", '1');
        alu_opa <= x"FFFFFFFE"; alu_opb <= x"00000001"; c_in <= '1';
        check_res("ADDC FE+1+T1=0 C1",   x"00000000", '1');
        alu_opa <= x"00000000"; alu_opb <= x"00000000"; c_in <= '0';
        check_res("ADDC 0+0+T0=0 C0",    x"00000000", '0');
        alu_opa <= x"00000000"; alu_opb <= x"00000000"; c_in <= '1';
        check_res("ADDC 0+0+T1=1 C0",    x"00000001", '0');
        alu_opa <= x"7FFFFFFF"; alu_opb <= x"00000000"; c_in <= '1';
        check_res("ADDC 7FFF+0+T1 C0",   x"80000000", '0');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"FFFFFFFF"; c_in <= '1';
        check_res("ADDC FF+FF+T1 C1",    x"FFFFFFFF", '1');

        -----------------------------------------------------------------------
        --  ADDV  Rn+Rm->Rn  Overflow->T
        --  f=PASSB  cin=ZERO  alu=ADDER  t=V
        -----------------------------------------------------------------------
        report ">>> ADDV" severity note;
        c_in_cmd <= CinCmd_ZERO;
        t_sel    <= TCmd_V;

        alu_opa <= x"00000005"; alu_opb <= x"00000003"; c_in <= '0';
        check_res("ADDV pos+pos no ovf",  x"00000008", '0');
        alu_opa <= x"7FFFFFFF"; alu_opb <= x"00000001";
        check_res("ADDV +overflow",       x"80000000", '1');
        alu_opa <= x"7FFFFFFF"; alu_opb <= x"7FFFFFFF";
        check_res("ADDV max+max +ovf",    x"FFFFFFFE", '1');
        alu_opa <= x"80000000"; alu_opb <= x"FFFFFFFF";
        check_res("ADDV -overflow",       x"7FFFFFFF", '1');
        alu_opa <= x"80000000"; alu_opb <= x"80000000";
        check_res("ADDV min+min -ovf",    x"00000000", '1');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"FFFFFFFF";   -- -1+-1=-2, no ovf
        check_res("ADDV neg+neg no ovf",  x"FFFFFFFE", '0');
        alu_opa <= x"7FFFFFFF"; alu_opb <= x"80000000";   -- max+min=-1, no ovf
        check_res("ADDV max+min no ovf",  x"FFFFFFFF", '0');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"00000001";   -- -1+1=0, no ovf
        check_res("ADDV -1+1=0 no ovf",   x"00000000", '0');

        -----------------------------------------------------------------------
        --  SUB  Rn-Rm->Rn  T unchanged
        --  f=NOTB  cin=ONE  alu=ADDER  t=HOLD
        -----------------------------------------------------------------------
        report ">>> SUB" severity note;
        f_cmd    <= FCmd_NOTB;
        c_in_cmd <= CinCmd_ONE;
        t_sel    <= TCmd_HOLD;

        alu_opa <= x"00000008"; alu_opb <= x"00000003"; c_in <= '0';
        check_res("SUB  8-3=5",          x"00000005", '0', false);
        alu_opa <= x"00000005"; alu_opb <= x"00000005";
        check_res("SUB  x-x=0",          x"00000000", '0', false);
        alu_opa <= x"00000003"; alu_opb <= x"00000008";
        check_res("SUB  3-8=-5",         x"FFFFFFFB", '0', false);
        alu_opa <= x"00000000"; alu_opb <= x"00000001";
        check_res("SUB  0-1=-1",         x"FFFFFFFF", '0', false);
        alu_opa <= x"00000000"; alu_opb <= x"00000000";
        check_res("SUB  0-0=0",          x"00000000", '0', false);
        alu_opa <= x"80000000"; alu_opb <= x"00000001";   -- signed ovf
        check_res("SUB  min-1=max",      x"7FFFFFFF", '0', false);
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"FFFFFFFF";
        check_res("SUB  max-max=0",      x"00000000", '0', false);
        alu_opa <= x"00000000"; alu_opb <= x"FFFFFFFF";   -- 0-(-1)=1
        check_res("SUB  0-(-1)=1",       x"00000001", '0', false);
        alu_opa <= x"7FFFFFFF"; alu_opb <= x"FFFFFFFF";   -- max-(-1) signed ovf
        check_res("SUB  max-(-1) ovf",   x"80000000", '0', false);
        -- T held through subtraction
        c_in <= '1';
        alu_opa <= x"00000008"; alu_opb <= x"00000003";
        wait for TPROP;
        n_tests.increment;
        if t_bit /= '0' then
            report "[FAIL] SUB  T held=0" severity error; n_fail.increment;
        else
            report "[PASS] SUB  T held=0" severity note;
        end if;
        c_in <= '0';

        -----------------------------------------------------------------------
        --  SUBC  Rn-Rm-T->Rn  Borrow->T
        --  f=NOTB  cin=CINBAR  alu=ADDER  t=C
        --
        --  Expected T is SH2-spec: T=1 means borrow occurred.
        --  Adder computes opa + ~opb + ~T_in; carry_out=1 ↔ no borrow.
        --  If TCmd_C exposes raw arithmetic carry (not borrow), flip exp_t.
        -----------------------------------------------------------------------
        report ">>> SUBC" severity note;
        c_in_cmd <= CinCmd_CINBAR;
        t_sel    <= TCmd_NC;

        alu_opa <= x"00000008"; alu_opb <= x"00000003"; c_in <= '0';
        check_res("SUBC 8-3-0=5 noborrow",  x"00000005", '0');
        alu_opa <= x"00000008"; alu_opb <= x"00000003"; c_in <= '1';
        check_res("SUBC 8-3-1=4 noborrow",  x"00000004", '0');
        alu_opa <= x"00000002"; alu_opb <= x"00000003"; c_in <= '0';
        check_res("SUBC 2-3-0 borrow",      x"FFFFFFFF", '1');
        alu_opa <= x"00000000"; alu_opb <= x"00000000"; c_in <= '1';
        check_res("SUBC 0-0-1 borrow",      x"FFFFFFFF", '1');
        alu_opa <= x"00000001"; alu_opb <= x"00000001"; c_in <= '0';
        check_res("SUBC 1-1-0=0 noborrow",  x"00000000", '0');
        alu_opa <= x"00000000"; alu_opb <= x"00000000"; c_in <= '0';
        check_res("SUBC 0-0-0=0 noborrow",  x"00000000", '0');
        alu_opa <= x"80000000"; alu_opb <= x"80000000"; c_in <= '0';
        check_res("SUBC min-min-0 noborrow",x"00000000", '0');
        alu_opa <= x"00000003"; alu_opb <= x"00000002"; c_in <= '1';
        check_res("SUBC 3-2-1=0 noborrow",  x"00000000", '0');
        alu_opa <= x"00000003"; alu_opb <= x"00000004"; c_in <= '1';
        check_res("SUBC 3-4-1=-2 borrow",   x"FFFFFFFE", '1');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"00000000"; c_in <= '0';
        check_res("SUBC maxu-0-0 noborrow", x"FFFFFFFF", '0');

        -----------------------------------------------------------------------
        --  SUBV  Rn-Rm->Rn  Overflow->T
        --  f=NOTB  cin=ONE  alu=ADDER  t=V
        -----------------------------------------------------------------------
        report ">>> SUBV" severity note;
        c_in_cmd <= CinCmd_ONE;
        t_sel    <= TCmd_V;

        alu_opa <= x"00000005"; alu_opb <= x"00000003"; c_in <= '0';
        check_res("SUBV 5-3=2 no ovf",    x"00000002", '0');
        alu_opa <= x"00000003"; alu_opb <= x"00000008";
        check_res("SUBV 3-8=-5 no ovf",   x"FFFFFFFB", '0');
        alu_opa <= x"80000000"; alu_opb <= x"00000001";   -- neg - pos -> +ovf
        check_res("SUBV min-1 +ovf",      x"7FFFFFFF", '1');
        alu_opa <= x"7FFFFFFF"; alu_opb <= x"FFFFFFFF";   -- pos - neg -> -ovf
        check_res("SUBV max-(-1) -ovf",   x"80000000", '1');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"FFFFFFFF";   -- -1-(-1)=0 no ovf
        check_res("SUBV -1-(-1)=0 no ovf",x"00000000", '0');
        alu_opa <= x"80000000"; alu_opb <= x"7FFFFFFF";   -- min-max ovf
        check_res("SUBV min-max +ovf",    x"00000001", '1');
        alu_opa <= x"00000000"; alu_opb <= x"00000000";
        check_res("SUBV 0-0=0 no ovf",    x"00000000", '0');
        alu_opa <= x"40000000"; alu_opb <= x"C0000000";   -- pos - neg -> -ovf
        check_res("SUBV pos-neg -ovf",    x"80000000", '1');

        -----------------------------------------------------------------------
        --  NEG  0-Rm->Rn  T unchanged
        --  opa=0  f=NOTB  cin=ONE  alu=ADDER  t=HOLD
        -----------------------------------------------------------------------
        report ">>> NEG" severity note;
        t_sel <= TCmd_HOLD;

        alu_opa <= x"00000000"; alu_opb <= x"00000005"; c_in <= '0';
        check_res("NEG  5->-5",           x"FFFFFFFB", '0', false);
        alu_opa <= x"00000000"; alu_opb <= x"00000001";
        check_res("NEG  1->-1",           x"FFFFFFFF", '0', false);
        alu_opa <= x"00000000"; alu_opb <= x"FFFFFFFF";   -- -(-1)=1
        check_res("NEG  -1->1",           x"00000001", '0', false);
        alu_opa <= x"00000000"; alu_opb <= x"00000000";
        check_res("NEG  0->0",            x"00000000", '0', false);
        alu_opa <= x"00000000"; alu_opb <= x"80000000";   -- -(min)=min (overflow)
        check_res("NEG  min->min",        x"80000000", '0', false);
        alu_opa <= x"00000000"; alu_opb <= x"7FFFFFFF";
        check_res("NEG  max_pos->min+1",  x"80000001", '0', false);

        -----------------------------------------------------------------------
        --  NEGC  0-Rm-T->Rn  Borrow->T
        --  opa=0  f=NOTB  cin=CINBAR  alu=ADDER  t=C
        --  Same borrow-convention note as SUBC.
        -----------------------------------------------------------------------
        report ">>> NEGC" severity note;
        c_in_cmd <= CinCmd_CINBAR;
        t_sel    <= TCmd_NC;

        alu_opa <= x"00000000"; alu_opb <= x"00000005"; c_in <= '0';
        check_res("NEGC 5 T0 borrow",    x"FFFFFFFB", '1');
        alu_opa <= x"00000000"; alu_opb <= x"00000005"; c_in <= '1';
        check_res("NEGC 5 T1 borrow",    x"FFFFFFFA", '1');
        alu_opa <= x"00000000"; alu_opb <= x"00000000"; c_in <= '0';
        check_res("NEGC 0 T0 noborrow",  x"00000000", '0');
        alu_opa <= x"00000000"; alu_opb <= x"00000000"; c_in <= '1';
        check_res("NEGC 0 T1 borrow",    x"FFFFFFFF", '1');
        alu_opa <= x"00000000"; alu_opb <= x"FFFFFFFF"; c_in <= '0';   -- 0-(-1)=1
        check_res("NEGC -1 T0 borrow", x"00000001", '1');
        alu_opa <= x"00000000"; alu_opb <= x"FFFFFFFF"; c_in <= '1';   -- 0-(-1)-1=0
        check_res("NEGC -1 T1 borrow", x"00000000", '1');

        -----------------------------------------------------------------------
        --  AND  Rn&Rm->Rn  T unchanged
        --  f=AND  alu=FBLOCK  t=HOLD
        -----------------------------------------------------------------------
        report ">>> AND" severity note;
        f_cmd    <= FCmd_AND;
        alu_cmd  <= ALUCmd_FBLOCK;
        c_in_cmd <= CinCmd_ZERO;
        t_sel    <= TCmd_HOLD;

        alu_opa <= x"000000FF"; alu_opb <= x"0000000F"; c_in <= '0';
        check_res("AND  FF&0F=0F",       x"0000000F", '0', false);
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"AAAAAAAA";
        check_res("AND  all1&AAA=AAA",   x"AAAAAAAA", '0', false);
        alu_opa <= x"DEADBEEF"; alu_opb <= x"00000000";
        check_res("AND  x&0=0",          x"00000000", '0', false);
        alu_opa <= x"DEADBEEF"; alu_opb <= x"FFFFFFFF";
        check_res("AND  x&all1=x",       x"DEADBEEF", '0', false);
        alu_opa <= x"A5A5A5A5"; alu_opb <= x"5A5A5A5A";
        check_res("AND  complement=0",   x"00000000", '0', false);
        alu_opa <= x"12345678"; alu_opb <= x"12345678";
        check_res("AND  idempotent",     x"12345678", '0', false);
        alu_opa <= x"55555555"; alu_opb <= x"AAAAAAAA";
        check_res("AND  alt compl=0",    x"00000000", '0', false);
        alu_opa <= x"F0F0F0F0"; alu_opb <= x"0F0F0F0F";
        check_res("AND  nibble compl=0", x"00000000", '0', false);
        alu_opa <= x"80000001"; alu_opb <= x"80000001";
        check_res("AND  self=self",      x"80000001", '0', false);

        -----------------------------------------------------------------------
        --  OR  Rn|Rm->Rn  T unchanged
        --  f=OR  alu=FBLOCK  t=HOLD
        -----------------------------------------------------------------------
        report ">>> OR" severity note;
        f_cmd <= FCmd_OR;

        alu_opa <= x"000000F0"; alu_opb <= x"0000000F"; c_in <= '0';
        check_res("OR   F0|0F=FF",       x"000000FF", '0', false);
        alu_opa <= x"DEADBEEF"; alu_opb <= x"00000000";
        check_res("OR   x|0=x",          x"DEADBEEF", '0', false);
        alu_opa <= x"12345678"; alu_opb <= x"FFFFFFFF";
        check_res("OR   x|all1=all1",    x"FFFFFFFF", '0', false);
        alu_opa <= x"A5A5A5A5"; alu_opb <= x"5A5A5A5A";
        check_res("OR   compl=all1",     x"FFFFFFFF", '0', false);
        alu_opa <= x"12345678"; alu_opb <= x"12345678";
        check_res("OR   idempotent",     x"12345678", '0', false);
        alu_opa <= x"55555555"; alu_opb <= x"AAAAAAAA";
        check_res("OR   alt compl=all1", x"FFFFFFFF", '0', false);
        alu_opa <= x"00000000"; alu_opb <= x"00000000";
        check_res("OR   0|0=0",          x"00000000", '0', false);
        alu_opa <= x"80000000"; alu_opb <= x"00000001";
        check_res("OR   MSB|LSB",        x"80000001", '0', false);

        -----------------------------------------------------------------------
        --  XOR  Rn^Rm->Rn  T unchanged
        --  f=XOR  alu=FBLOCK  t=HOLD
        -----------------------------------------------------------------------
        report ">>> XOR" severity note;
        f_cmd <= FCmd_XOR;

        alu_opa <= x"000000FF"; alu_opb <= x"0000000F"; c_in <= '0';
        check_res("XOR  FF^0F=F0",       x"000000F0", '0', false);
        alu_opa <= x"DEADBEEF"; alu_opb <= x"DEADBEEF";
        check_res("XOR  self=0",         x"00000000", '0', false);
        alu_opa <= x"12345678"; alu_opb <= x"00000000";
        check_res("XOR  x^0=x",          x"12345678", '0', false);
        alu_opa <= x"12345678"; alu_opb <= x"FFFFFFFF";   -- XOR with all-1 = NOT
        check_res("XOR  x^all1=~x",      x"EDCBA987", '0', false);
        alu_opa <= x"A5A5A5A5"; alu_opb <= x"5A5A5A5A";
        check_res("XOR  compl=all1",     x"FFFFFFFF", '0', false);
        alu_opa <= x"55555555"; alu_opb <= x"AAAAAAAA";
        check_res("XOR  alt compl=all1", x"FFFFFFFF", '0', false);
        alu_opa <= x"00000000"; alu_opb <= x"00000000";
        check_res("XOR  0^0=0",          x"00000000", '0', false);
        alu_opa <= x"F0F0F0F0"; alu_opb <= x"0F0F0F0F";
        check_res("XOR  nibble=all1",    x"FFFFFFFF", '0', false);

        -----------------------------------------------------------------------
        --  NOT  ~Rm->Rn  T unchanged
        --  f=NOTA  alu=FBLOCK  t=HOLD  (opa=source; opb don't-care)
        -----------------------------------------------------------------------
        report ">>> NOT" severity note;
        f_cmd <= FCmd_NOTA;

        alu_opa <= x"00000000"; alu_opb <= x"DEADBEEF"; c_in <= '0';
        check_res("NOT  ~0=all1",        x"FFFFFFFF", '0', false);
        alu_opa <= x"FFFFFFFF";
        check_res("NOT  ~all1=0",        x"00000000", '0', false);
        alu_opa <= x"A5A5A5A5";
        check_res("NOT  ~A5A5=5A5A",     x"5A5A5A5A", '0', false);
        alu_opa <= x"5A5A5A5A";
        check_res("NOT  ~5A5A=A5A5",     x"A5A5A5A5", '0', false);
        alu_opa <= x"12345678";
        check_res("NOT  ~12345678",      x"EDCBA987", '0', false);
        alu_opa <= x"80000000";
        check_res("NOT  ~min=max_pos",   x"7FFFFFFF", '0', false);
        alu_opa <= x"7FFFFFFF";
        check_res("NOT  ~max=min_neg",   x"80000000", '0', false);
        alu_opa <= x"55555555";
        check_res("NOT  ~5555=AAAA",     x"AAAAAAAA", '0', false);

        -----------------------------------------------------------------------
        --  TST  Rn&Rm; T=1 if result=0
        --  f=AND  alu=FBLOCK  t=Z
        -----------------------------------------------------------------------
        report ">>> TST" severity note;
        f_cmd <= FCmd_AND;
        t_sel <= TCmd_Z;

        alu_opa <= x"000000FF"; alu_opb <= x"00000000"; c_in <= '0';
        check_res("TST  FF&00=0 T1",     x"00000000", '1');
        alu_opa <= x"000000FF"; alu_opb <= x"00000001";
        check_res("TST  FF&01!=0 T0",    x"00000001", '0');
        alu_opa <= x"A5A5A5A5"; alu_opb <= x"5A5A5A5A";
        check_res("TST  compl=0 T1",     x"00000000", '1');
        alu_opa <= x"DEADBEEF"; alu_opb <= x"DEADBEEF";
        check_res("TST  self!=0 T0",     x"DEADBEEF", '0');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"FFFFFFFF";
        check_res("TST  all1&all1 T0",   x"FFFFFFFF", '0');
        alu_opa <= x"80000000"; alu_opb <= x"80000000";
        check_res("TST  MSB only T0",    x"80000000", '0');
        alu_opa <= x"55555555"; alu_opb <= x"00000001";
        check_res("TST  LSB shared T0",  x"00000001", '0');
        alu_opa <= x"55555555"; alu_opb <= x"AAAAAAAA";
        check_res("TST  alt compl T1",   x"00000000", '1');
        alu_opa <= x"00000001"; alu_opb <= x"00000001";
        check_res("TST  LSB shared T0b", x"00000001", '0');

        -----------------------------------------------------------------------
        --  CMP/EQ  if Rn=Rm T=1
        --  f=NOTB  cin=ONE  alu=ADDER  t=Z
        -----------------------------------------------------------------------
        report ">>> CMP/EQ" severity note;
        f_cmd    <= FCmd_NOTB;
        c_in_cmd <= CinCmd_ONE;
        alu_cmd  <= ALUCmd_ADDER;
        t_sel    <= TCmd_Z;

        alu_opa <= x"00000005"; alu_opb <= x"00000005"; c_in <= '0';
        check_res("CMP/EQ equal T1",     x"00000000", '1');
        alu_opa <= x"00000006"; alu_opb <= x"00000005";
        check_res("CMP/EQ greater T0",   x"00000001", '0');
        alu_opa <= x"00000004"; alu_opb <= x"00000005";
        check_res("CMP/EQ less T0",      x"FFFFFFFF", '0');
        alu_opa <= x"00000000"; alu_opb <= x"00000000";
        check_res("CMP/EQ both 0 T1",    x"00000000", '1');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"FFFFFFFF";
        check_res("CMP/EQ both all1 T1", x"00000000", '1');
        alu_opa <= x"80000000"; alu_opb <= x"80000000";
        check_res("CMP/EQ both min T1",  x"00000000", '1');
        alu_opa <= x"7FFFFFFF"; alu_opb <= x"80000000";
        check_res("CMP/EQ max!=min T0",  x"FFFFFFFF", '0');
        alu_opa <= x"00000001"; alu_opb <= x"00000000";
        check_res("CMP/EQ 1!=0 T0",      x"00000001", '0');

        -----------------------------------------------------------------------
        --  CMP/HS  unsigned Rn>=Rm T=1
        --  f=NOTB  cin=ONE  alu=ADDER  t=C
        -----------------------------------------------------------------------
        report ">>> CMP/HS" severity note;
        t_sel <= TCmd_C;

        alu_opa <= x"00000005"; alu_opb <= x"00000003"; c_in <= '0';
        check_res("CMP/HS 5>=3 T1",      x"00000002", '1');
        alu_opa <= x"00000003"; alu_opb <= x"00000003";
        check_res("CMP/HS equal T1",     x"00000000", '1');
        alu_opa <= x"00000002"; alu_opb <= x"00000003";
        check_res("CMP/HS 2<3 T0",       x"FFFFFFFF", '0');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"00000000";
        check_res("CMP/HS maxu>=0 T1",   x"FFFFFFFF", '1');
        alu_opa <= x"00000000"; alu_opb <= x"FFFFFFFF";
        check_res("CMP/HS 0<maxu T0",    x"00000001", '0');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"FFFFFFFF";
        check_res("CMP/HS maxu>=maxu T1",x"00000000", '1');
        alu_opa <= x"80000000"; alu_opb <= x"7FFFFFFF";   -- MSB set > no MSB (unsigned)
        check_res("CMP/HS MSB>noMSB T1", x"00000001", '1');
        alu_opa <= x"7FFFFFFF"; alu_opb <= x"80000000";
        check_res("CMP/HS noMSB<MSB T0", x"FFFFFFFF", '0');

        -----------------------------------------------------------------------
        --  CMP/GE  signed Rn>=Rm T=1   (S XNOR V)
        --  f=NOTB  cin=ONE  alu=ADDER  t=SXNORV
        -----------------------------------------------------------------------
        report ">>> CMP/GE" severity note;
        t_sel <= TCmd_SXNORV;

        alu_opa <= x"00000005"; alu_opb <= x"00000003"; c_in <= '0';
        check_res("CMP/GE 5>=3 T1",      x"00000002", '1');
        alu_opa <= x"00000003"; alu_opb <= x"00000003";
        check_res("CMP/GE equal T1",     x"00000000", '1');
        alu_opa <= x"00000002"; alu_opb <= x"00000003";
        check_res("CMP/GE 2<3 T0",       x"FFFFFFFF", '0');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"FFFFFFFE";   -- -1 >= -2
        check_res("CMP/GE -1>=-2 T1",   x"00000001", '1');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"00000000";   -- -1 < 0
        check_res("CMP/GE -1<0 T0",     x"FFFFFFFF", '0');
        alu_opa <= x"00000000"; alu_opb <= x"FFFFFFFF";   -- 0 >= -1
        check_res("CMP/GE 0>=-1 T1",    x"00000001", '1');
        alu_opa <= x"80000000"; alu_opb <= x"7FFFFFFF";   -- min < max
        check_res("CMP/GE min<max T0",   x"00000001", '0');
        alu_opa <= x"7FFFFFFF"; alu_opb <= x"80000000";   -- max > min
        check_res("CMP/GE max>=min T1",  x"FFFFFFFF", '1');
        alu_opa <= x"80000000"; alu_opb <= x"80000000";
        check_res("CMP/GE min>=min T1",  x"00000000", '1');

        -----------------------------------------------------------------------
        --  CMP/HI  unsigned Rn>Rm T=1   (C AND NOT Z)
        --  f=NOTB  cin=ONE  alu=ADDER  t=CNZ
        -----------------------------------------------------------------------
        report ">>> CMP/HI" severity note;
        t_sel <= TCmd_CNZ;

        alu_opa <= x"00000005"; alu_opb <= x"00000003"; c_in <= '0';
        check_res("CMP/HI 5>3 T1",       x"00000002", '1');
        alu_opa <= x"00000003"; alu_opb <= x"00000003";   -- equal -> not >
        check_res("CMP/HI equal T0",     x"00000000", '0');
        alu_opa <= x"00000002"; alu_opb <= x"00000003";
        check_res("CMP/HI 2<3 T0",       x"FFFFFFFF", '0');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"00000000";
        check_res("CMP/HI maxu>0 T1",    x"FFFFFFFF", '1');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"FFFFFFFE";
        check_res("CMP/HI maxu>maxu-1",  x"00000001", '1');
        alu_opa <= x"00000000"; alu_opb <= x"00000000";
        check_res("CMP/HI 0=0 T0",       x"00000000", '0');
        alu_opa <= x"00000001"; alu_opb <= x"00000000";
        check_res("CMP/HI 1>0 T1",       x"00000001", '1');

        -----------------------------------------------------------------------
        --  CMP/GT  signed Rn>Rm T=1   ((S XNOR V) AND NOT Z)
        --  f=NOTB  cin=ONE  alu=ADDER  t=SXNORVNZ
        -----------------------------------------------------------------------
        report ">>> CMP/GT" severity note;
        t_sel <= TCmd_SXNORVNZ;

        alu_opa <= x"00000005"; alu_opb <= x"00000003"; c_in <= '0';
        check_res("CMP/GT 5>3 T1",       x"00000002", '1');
        alu_opa <= x"00000003"; alu_opb <= x"00000003";
        check_res("CMP/GT equal T0",     x"00000000", '0');
        alu_opa <= x"00000002"; alu_opb <= x"00000003";
        check_res("CMP/GT 2<3 T0",       x"FFFFFFFF", '0');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"FFFFFFFE";   -- -1 > -2
        check_res("CMP/GT -1>-2 T1",    x"00000001", '1');
        alu_opa <= x"00000000"; alu_opb <= x"FFFFFFFF";   -- 0 > -1
        check_res("CMP/GT 0>-1 T1",     x"00000001", '1');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"00000000";   -- -1 < 0
        check_res("CMP/GT -1<0 T0",     x"FFFFFFFF", '0');
        alu_opa <= x"7FFFFFFF"; alu_opb <= x"80000000";   -- max > min
        check_res("CMP/GT max>min T1",   x"FFFFFFFF", '1');
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"FFFFFFFF";
        check_res("CMP/GT -1=-1 T0",    x"00000000", '0');
        alu_opa <= x"80000000"; alu_opb <= x"7FFFFFFF";   -- min < max
        check_res("CMP/GT min<max T0",   x"00000001", '0');

        -----------------------------------------------------------------------
        --  CMP/PZ  Rn>=0 T=1   (NOT sign bit)
        --  f=PASSA  alu=FBLOCK  t=NS
        -----------------------------------------------------------------------
        report ">>> CMP/PZ" severity note;
        f_cmd   <= FCmd_PASSA;
        alu_cmd <= ALUCmd_FBLOCK;
        t_sel   <= TCmd_NS;

        alu_opa <= x"00000005"; alu_opb <= x"00000000"; c_in <= '0';
        check_res("CMP/PZ +5>=0 T1",     x"00000005", '1');
        alu_opa <= x"00000000";
        check_res("CMP/PZ 0>=0 T1",      x"00000000", '1');
        alu_opa <= x"FFFFFFFF";
        check_res("CMP/PZ -1<0 T0",      x"FFFFFFFF", '0');
        alu_opa <= x"80000000";
        check_res("CMP/PZ min_neg<0 T0", x"80000000", '0');
        alu_opa <= x"7FFFFFFF";
        check_res("CMP/PZ max_pos>=0 T1",x"7FFFFFFF", '1');
        alu_opa <= x"00000001";
        check_res("CMP/PZ 1>=0 T1",      x"00000001", '1');
        alu_opa <= x"80000001";
        check_res("CMP/PZ 80000001<0 T0",x"80000001", '0');

        -----------------------------------------------------------------------
        --  CMP/PL  Rn>0 T=1   (NOT sign AND NOT zero)
        --  f=PASSA  alu=FBLOCK  t=NSNZ
        -----------------------------------------------------------------------
        report ">>> CMP/PL" severity note;
        t_sel <= TCmd_NSNZ;

        alu_opa <= x"00000005";
        check_res("CMP/PL +5>0 T1",      x"00000005", '1');
        alu_opa <= x"00000000";
        check_res("CMP/PL 0 not>0 T0",   x"00000000", '0');
        alu_opa <= x"FFFFFFFF";
        check_res("CMP/PL -1<0 T0",      x"FFFFFFFF", '0');
        alu_opa <= x"80000000";
        check_res("CMP/PL min_neg<0 T0", x"80000000", '0');
        alu_opa <= x"7FFFFFFF";
        check_res("CMP/PL max_pos>0 T1", x"7FFFFFFF", '1');
        alu_opa <= x"00000001";
        check_res("CMP/PL 1>0 T1",       x"00000001", '1');

        -----------------------------------------------------------------------
        --  CMP/STR  any byte of Rn equals corresponding byte of Rm -> T=1
        --  f=XOR  alu=FBLOCK  t=CMPSTR
        --  XOR byte=0 where bytes matched
        -----------------------------------------------------------------------
        report ">>> CMP/STR" severity note;
        f_cmd <= FCmd_XOR;
        t_sel <= TCmd_CMPSTR;

        alu_opa <= x"DEADBEEF"; alu_opb <= x"DEADBEEF"; c_in <= '0';
        check_res("CMP/STR all_match T1",  x"00000000", '1');
        alu_opa <= x"01020304"; alu_opb <= x"05060708";
        check_res("CMP/STR no_match T0",   x"0404040C", '0');
        alu_opa <= x"01020304"; alu_opb <= x"F1F2F304";   -- byte0=04 matches
        check_res("CMP/STR byte0_match T1",x"F0F0F000", '1');
        alu_opa <= x"DEAD00EF"; alu_opb <= x"BEEF00CF";   -- byte1=00 matches
        check_res("CMP/STR byte1_match T1",x"60420020", '1');
        --   DE^BE=60  AD^EF=42  00^00=00  EF^CF=20 -> 0x60420020
        alu_opa <= x"DEAD1234"; alu_opb <= x"BEADF123";   -- byte2=AD matches
        check_res("CMP/STR byte2_match T1",x"6000E317", '1');
        --   DE^BE=60  AD^AD=00  12^F1=E3  34^23=17 -> 0x6000E317
        alu_opa <= x"DE123456"; alu_opb <= x"DE789ABC";   -- byte3=DE matches
        check_res("CMP/STR byte3_match T1",x"006AAEEA", '1');
        --   DE^DE=00  12^78=6A  34^9A=AE  56^BC=EA -> 0x006AAEEA
        alu_opa <= x"AABBCCDD"; alu_opb <= x"AAFFCC11";   -- bytes 3 and 1 match
        check_res("CMP/STR multi_match T1",x"004400CC", '1');
        --   AA^AA=00  BB^FF=44  CC^CC=00  DD^11=CC -> 0x004400CC

        -----------------------------------------------------------------------
        --  DT  Rn-1->Rn; T=1 if result=0
        --  opa=Rn  opb=1 constant  f=NOTB  cin=ONE  alu=ADDER  t=Z
        -----------------------------------------------------------------------
        report ">>> DT" severity note;
        f_cmd    <= FCmd_NOTB;
        c_in_cmd <= CinCmd_ONE;
        alu_cmd  <= ALUCmd_ADDER;
        t_sel    <= TCmd_Z;

        alu_opa <= x"00000001"; alu_opb <= x"00000001"; c_in <= '0';
        check_res("DT 1->0 T1",           x"00000000", '1');
        alu_opa <= x"00000002"; alu_opb <= x"00000001";
        check_res("DT 2->1 T0",           x"00000001", '0');
        alu_opa <= x"00000003"; alu_opb <= x"00000001";
        check_res("DT 3->2 T0",           x"00000002", '0');
        alu_opa <= x"00000000"; alu_opb <= x"00000001";   -- 0-1 underflows
        check_res("DT 0-1 underflow T0", x"FFFFFFFF", '0');
        alu_opa <= x"80000001"; alu_opb <= x"00000001";
        check_res("DT 80000001->80000000",x"80000000", '0');
        alu_opa <= x"80000000"; alu_opb <= x"00000001";   -- sign boundary
        check_res("DT 80000000->7FFFFFFF",x"7FFFFFFF", '0');
        alu_opa <= x"00000064"; alu_opb <= x"00000001";   -- 100->99
        check_res("DT 100->99 T0",        x"00000063", '0');

        -----------------------------------------------------------------------
        -- =================================================================
        --  SINGLE-BIT SHIFTS via internal ALU shifter
        --  alu=SHIFT  res_sel=ALU  (c_in=don't-care unless noted)
        -- =================================================================
        -----------------------------------------------------------------------

        -----------------------------------------------------------------------
        --  SHLL / SHAL  T ← Rn ← 0
        --  s=LSL  cin=ZERO  alu=SHIFT  t=C
        --  SHAL is identical to SHLL in SH2.
        -----------------------------------------------------------------------
        report ">>> SHLL/SHAL" severity note;
        f_cmd    <= FCmd_PASSA;   -- don't-care for shift path
        c_in_cmd <= CinCmd_ZERO;
        s_cmd    <= SCmd_LSL;
        alu_cmd  <= ALUCmd_SHIFT;
        res_sel  <= ResSel_ALU;
        t_sel    <= TCmd_C;

        alu_opa <= x"00000001"; c_in <= '0';
        check_res("SHLL 1->2 T0",         x"00000002", '0');
        alu_opa <= x"80000000";           -- MSB shifts out
        check_res("SHLL MSB1->0 T1",      x"00000000", '1');
        alu_opa <= x"40000000";           -- becomes MSB
        check_res("SHLL 40000000 T0",    x"80000000", '0');
        alu_opa <= x"00000000";
        check_res("SHLL 0->0 T0",         x"00000000", '0');
        alu_opa <= x"FFFFFFFF";
        check_res("SHLL all1 T1",        x"FFFFFFFE", '1');
        alu_opa <= x"55555555";           -- 0101...->1010... T0
        check_res("SHLL 5555->AAAA T0",   x"AAAAAAAA", '0');
        alu_opa <= x"AAAAAAAA";           -- 1010...->0101..._0 T1
        check_res("SHLL AAAA->5554 T1",   x"55555554", '1');
        alu_opa <= x"7FFFFFFF";           -- no MSB before, LSB=1
        check_res("SHLL 7FFFFFFF T0",    x"FFFFFFFE", '0');

        -----------------------------------------------------------------------
        --  SHLR  0 -> Rn -> T   (logical right 1)
        --  s=LSR  cin=ZERO  alu=SHIFT  t=C
        -----------------------------------------------------------------------
        report ">>> SHLR" severity note;
        s_cmd <= SCmd_LSR;

        alu_opa <= x"00000002"; c_in <= '0';
        check_res("SHLR 2->1 T0",         x"00000001", '0');
        alu_opa <= x"00000001";           -- LSB shifts out
        check_res("SHLR 1->0 T1",         x"00000000", '1');
        alu_opa <= x"80000000";           -- logical: 0-fill
        check_res("SHLR 80000000 T0",    x"40000000", '0');
        alu_opa <= x"FFFFFFFF";
        check_res("SHLR all1 T1",        x"7FFFFFFF", '1');
        alu_opa <= x"00000000";
        check_res("SHLR 0->0 T0",         x"00000000", '0');
        alu_opa <= x"AAAAAAAA";           -- 1010...->0101... T0
        check_res("SHLR AAAA->5555 T0",   x"55555555", '0');
        alu_opa <= x"55555555";           -- 0101...->0010... T1
        check_res("SHLR 5555->2AAA T1",   x"2AAAAAAA", '1');

        -----------------------------------------------------------------------
        --  SHAR  MSB -> Rn -> T   (arithmetic right 1)
        --  s=ASR  cin=ZERO  alu=SHIFT  t=C
        -----------------------------------------------------------------------
        report ">>> SHAR" severity note;
        s_cmd <= SCmd_ASR;

        alu_opa <= x"80000000"; c_in <= '0';   -- sign extends
        check_res("SHAR 80000000 T0",    x"C0000000", '0');
        alu_opa <= x"FFFFFFFF";           -- -1 >> 1 = -1 (T=1)
        check_res("SHAR -1 stays T1",    x"FFFFFFFF", '1');
        alu_opa <= x"00000002";
        check_res("SHAR 2->1 T0",         x"00000001", '0');
        alu_opa <= x"00000001";
        check_res("SHAR 1->0 T1",         x"00000000", '1');
        alu_opa <= x"7FFFFFFF";
        check_res("SHAR 7FFFFFFF T1",    x"3FFFFFFF", '1');
        alu_opa <= x"C0000000";           -- negative, sign extends
        check_res("SHAR C0000000 T0",    x"E0000000", '0');
        alu_opa <= x"40000000";
        check_res("SHAR 40000000 T0",    x"20000000", '0');

        -----------------------------------------------------------------------
        --  ROTL  T ← Rn ← MSB   (MSB->bit0 and->T)
        --  s=ROL  cin=ZERO  alu=SHIFT  t=C
        -----------------------------------------------------------------------
        report ">>> ROTL" severity note;
        s_cmd    <= SCmd_ROL;
        c_in_cmd <= CinCmd_ZERO;

        alu_opa <= x"80000000"; c_in <= '0';
        check_res("ROTL MSB1->bit0+T1",   x"00000001", '1');
        alu_opa <= x"00000001";
        check_res("ROTL bit0->bit1 T0",   x"00000002", '0');
        alu_opa <= x"40000000";
        check_res("ROTL 40000000 T0",    x"80000000", '0');
        alu_opa <= x"FFFFFFFF";
        check_res("ROTL all1 stays T1",  x"FFFFFFFF", '1');
        alu_opa <= x"00000000";
        check_res("ROTL 0 stays T0",     x"00000000", '0');
        alu_opa <= x"A5A5A5A5";           -- MSB=1 -> 0x4B4B4B4B T1
        check_res("ROTL A5A5->4B4B T1",   x"4B4B4B4B", '1');
        alu_opa <= x"5A5A5A5A";           -- MSB=0 -> 0xB4B4B4B4 T0
        check_res("ROTL 5A5A->B4B4 T0",   x"B4B4B4B4", '0');

        -----------------------------------------------------------------------
        --  ROTR  LSB -> Rn -> T   (LSB->MSB and->T)
        --  s=ROR  cin=ZERO  alu=SHIFT  t=C
        -----------------------------------------------------------------------
        report ">>> ROTR" severity note;
        s_cmd <= SCmd_ROR;

        alu_opa <= x"00000001"; c_in <= '0';   -- LSB->MSB+T
        check_res("ROTR LSB1->MSB T1",    x"80000000", '1');
        alu_opa <= x"80000000";
        check_res("ROTR 80000000 T0",    x"40000000", '0');
        alu_opa <= x"00000002";
        check_res("ROTR 2->1 T0",         x"00000001", '0');
        alu_opa <= x"FFFFFFFF";
        check_res("ROTR all1 stays T1",  x"FFFFFFFF", '1');
        alu_opa <= x"00000000";
        check_res("ROTR 0 stays T0",     x"00000000", '0');
        alu_opa <= x"A5A5A5A5";           -- LSB=1 -> 0xD2D2D2D2 T1
        check_res("ROTR A5A5->D2D2 T1",   x"D2D2D2D2", '1');
        alu_opa <= x"5A5A5A5A";           -- LSB=0 -> 0x2D2D2D2D T0
        check_res("ROTR 5A5A->2D2D T0",   x"2D2D2D2D", '0');

        -----------------------------------------------------------------------
        --  ROTCL  T ← Rn ← T   (rotate left through carry)
        --  s=RLC  cin=CIN  alu=SHIFT  t=C
        -----------------------------------------------------------------------
        report ">>> ROTCL" severity note;
        s_cmd    <= SCmd_RLC;
        c_in_cmd <= CinCmd_CIN;

        alu_opa <= x"80000000"; c_in <= '0';   -- MSB=1->newT=1; old T fills bit0
        check_res("ROTCL MSB1 T0->0 nT1", x"00000000", '1');
        alu_opa <= x"80000000"; c_in <= '1';
        check_res("ROTCL MSB1 T1->1 nT1", x"00000001", '1');
        alu_opa <= x"40000000"; c_in <= '0';
        check_res("ROTCL 40000000 T0",   x"80000000", '0');
        alu_opa <= x"40000000"; c_in <= '1';
        check_res("ROTCL 40000000 T1",   x"80000001", '0');
        alu_opa <= x"00000001"; c_in <= '0';
        check_res("ROTCL bit0 T0->2",     x"00000002", '0');
        alu_opa <= x"00000001"; c_in <= '1';
        check_res("ROTCL bit0 T1->3",     x"00000003", '0');
        alu_opa <= x"7FFFFFFF"; c_in <= '0';
        check_res("ROTCL 7FFFFFFF T0",   x"FFFFFFFE", '0');
        alu_opa <= x"7FFFFFFF"; c_in <= '1';
        check_res("ROTCL 7FFFFFFF T1",   x"FFFFFFFF", '0');
        alu_opa <= x"FFFFFFFF"; c_in <= '1';
        check_res("ROTCL all1 T1",       x"FFFFFFFF", '1');
        alu_opa <= x"FFFFFFFF"; c_in <= '0';
        check_res("ROTCL all1 T0",       x"FFFFFFFE", '1');

        -----------------------------------------------------------------------
        --  ROTCR  T -> Rn -> T   (rotate right through carry)
        --  s=RRC  cin=CIN  alu=SHIFT  t=C
        -----------------------------------------------------------------------
        report ">>> ROTCR" severity note;
        s_cmd <= SCmd_RRC;

        alu_opa <= x"00000001"; c_in <= '0';   -- LSB=1->newT=1; old T fills MSB
        check_res("ROTCR LSB1 T0->0 nT1", x"00000000", '1');
        alu_opa <= x"00000001"; c_in <= '1';
        check_res("ROTCR LSB1 T1->80M nT1",x"80000000", '1');
        alu_opa <= x"80000000"; c_in <= '0';
        check_res("ROTCR 80000000 T0",   x"40000000", '0');
        alu_opa <= x"80000000"; c_in <= '1';
        check_res("ROTCR 80000000 T1",   x"C0000000", '0');
        alu_opa <= x"FFFFFFFF"; c_in <= '0';
        check_res("ROTCR all1 T0",       x"7FFFFFFF", '1');
        alu_opa <= x"FFFFFFFF"; c_in <= '1';
        check_res("ROTCR all1 T1",       x"FFFFFFFF", '1');
        alu_opa <= x"00000002"; c_in <= '0';
        check_res("ROTCR 2 T0->1",        x"00000001", '0');
        alu_opa <= x"00000002"; c_in <= '1';
        check_res("ROTCR 2 T1->80000001", x"80000001", '0');
        alu_opa <= x"00000000"; c_in <= '1';
        check_res("ROTCR 0 T1->80000000", x"80000000", '0');

        -----------------------------------------------------------------------
        -- =================================================================
        --  MULTI-BIT SHIFTS via external barrel shifters
        --  alu=SHIFT  t=HOLD  (T unchanged for all ×2/×8/×16 instructions)
        -- =================================================================
        -----------------------------------------------------------------------

        -----------------------------------------------------------------------
        --  SHLL2  Rn<<2->Rn  T unchanged
        --  s=LSL  res_sel=Shift2
        -----------------------------------------------------------------------
        report ">>> SHLL2" severity note;
        s_cmd     <= SCmd_LSL;
        c_in_cmd  <= CinCmd_ZERO;
        alu_cmd   <= ALUCmd_SHIFT;
        shift_sel <= 0;
        res_sel   <= ResSel_Shift2;
        t_sel     <= TCmd_HOLD;

        alu_opa <= x"00000001"; c_in <= '0';
        check_res("SHLL2 1->4",           x"00000004", '0', false);
        alu_opa <= x"00000003";
        check_res("SHLL2 3->12",          x"0000000C", '0', false);
        alu_opa <= x"40000000";           -- top 2 bits lost
        check_res("SHLL2 40000000->0",    x"00000000", '0', false);
        alu_opa <= x"80000000";
        check_res("SHLL2 80000000->0",    x"00000000", '0', false);
        alu_opa <= x"12345678";           -- ×4
        check_res("SHLL2 12345678",      x"48D159E0", '0', false);
        alu_opa <= x"3FFFFFFF";           -- max that fits
        check_res("SHLL2 3FFFFFFF",      x"FFFFFFFC", '0', false);
        alu_opa <= x"AAAAAAAA";           -- 1010...1010 -> 1010...1000
        check_res("SHLL2 AAAAAAAA",      x"AAAAAAA8", '0', false);
        alu_opa <= x"55555555";           -- 0101...0101 -> 0101...0100
        check_res("SHLL2 55555555",      x"55555554", '0', false);
        alu_opa <= x"00000000";
        check_res("SHLL2 0->0",           x"00000000", '0', false);

        -----------------------------------------------------------------------
        --  SHLR2  Rn>>2->Rn  T unchanged (logical)
        --  s=LSR  res_sel=Shift2
        -----------------------------------------------------------------------
        report ">>> SHLR2" severity note;
        s_cmd <= SCmd_LSR;

        alu_opa <= x"00000004"; c_in <= '0';
        check_res("SHLR2 4->1",           x"00000001", '0', false);
        alu_opa <= x"00000003";           -- bits lost
        check_res("SHLR2 3->0",           x"00000000", '0', false);
        alu_opa <= x"80000000";           -- 0-fill from MSB
        check_res("SHLR2 80000000",      x"20000000", '0', false);
        alu_opa <= x"12345678";
        check_res("SHLR2 12345678",      x"048D159E", '0', false);
        alu_opa <= x"FFFFFFFF";
        check_res("SHLR2 FFFFFFFF",      x"3FFFFFFF", '0', false);
        alu_opa <= x"00000000";
        check_res("SHLR2 0->0",           x"00000000", '0', false);
        alu_opa <= x"AAAAAAAA";           -- 1010...1010 -> 0010...1010
        check_res("SHLR2 AAAAAAAA",      x"2AAAAAAA", '0', false);

        -----------------------------------------------------------------------
        --  SHLL8  Rn<<8->Rn  T unchanged
        --  s=LSL  res_sel=Shift8
        -----------------------------------------------------------------------
        report ">>> SHLL8" severity note;
        s_cmd     <= SCmd_LSL;
        shift_sel <= 1;
        res_sel   <= ResSel_Shift8;

        alu_opa <= x"00000001"; c_in <= '0';
        check_res("SHLL8 1->100",         x"00000100", '0', false);
        alu_opa <= x"12345678";           -- top byte 12 discarded
        check_res("SHLL8 12345678",      x"34567800", '0', false);
        alu_opa <= x"FF000000";           -- top byte discarded
        check_res("SHLL8 FF000000->0",    x"00000000", '0', false);
        alu_opa <= x"00FFFFFF";
        check_res("SHLL8 00FFFFFF",      x"FFFFFF00", '0', false);
        alu_opa <= x"00000000";
        check_res("SHLL8 0->0",           x"00000000", '0', false);
        alu_opa <= x"000000FF";
        check_res("SHLL8 FF->FF00",       x"0000FF00", '0', false);
        alu_opa <= x"DEADBEEF";
        check_res("SHLL8 DEADBEEF",      x"ADBEEF00", '0', false);

        -----------------------------------------------------------------------
        --  SHLR8  Rn>>8->Rn  T unchanged (logical)
        --  s=LSR  res_sel=Shift8
        -----------------------------------------------------------------------
        report ">>> SHLR8" severity note;
        s_cmd <= SCmd_LSR;

        alu_opa <= x"12345678"; c_in <= '0';
        check_res("SHLR8 12345678",      x"00123456", '0', false);
        alu_opa <= x"FF000000";
        check_res("SHLR8 FF000000",      x"00FF0000", '0', false);
        alu_opa <= x"000000FF";           -- bottom byte shifts away
        check_res("SHLR8 000000FF->0",    x"00000000", '0', false);
        alu_opa <= x"FFFFFF00";
        check_res("SHLR8 FFFFFF00",      x"00FFFFFF", '0', false);
        alu_opa <= x"00000000";
        check_res("SHLR8 0->0",           x"00000000", '0', false);
        alu_opa <= x"DEADBEEF";
        check_res("SHLR8 DEADBEEF",      x"00DEADBE", '0', false);

        -----------------------------------------------------------------------
        --  SHLL16  Rn<<16->Rn  T unchanged
        --  s=LSL  res_sel=Shift16
        -----------------------------------------------------------------------
        report ">>> SHLL16" severity note;
        s_cmd     <= SCmd_LSL;
        shift_sel <= 2;
        res_sel   <= ResSel_Shift16;

        alu_opa <= x"00000001"; c_in <= '0';
        check_res("SHLL16 1->10000",      x"00010000", '0', false);
        alu_opa <= x"12345678";           -- top word 1234 discarded
        check_res("SHLL16 12345678",     x"56780000", '0', false);
        alu_opa <= x"FFFF0000";           -- top word discarded
        check_res("SHLL16 FFFF0000->0",   x"00000000", '0', false);
        alu_opa <= x"0000FFFF";
        check_res("SHLL16 0000FFFF",     x"FFFF0000", '0', false);
        alu_opa <= x"00000000";
        check_res("SHLL16 0->0",          x"00000000", '0', false);
        alu_opa <= x"DEADBEEF";
        check_res("SHLL16 DEADBEEF",     x"BEEF0000", '0', false);

        -----------------------------------------------------------------------
        --  SHLR16  Rn>>16->Rn  T unchanged (logical)
        --  s=LSR  res_sel=Shift16
        -----------------------------------------------------------------------
        report ">>> SHLR16" severity note;
        s_cmd <= SCmd_LSR;

        alu_opa <= x"12345678"; c_in <= '0';
        check_res("SHLR16 12345678",     x"00001234", '0', false);
        alu_opa <= x"FFFF0000";
        check_res("SHLR16 FFFF0000",     x"0000FFFF", '0', false);
        alu_opa <= x"0000FFFF";           -- lower word shifts away
        check_res("SHLR16 0000FFFF->0",   x"00000000", '0', false);
        alu_opa <= x"DEADBEEF";
        check_res("SHLR16 DEADBEEF",     x"0000DEAD", '0', false);
        alu_opa <= x"00000000";
        check_res("SHLR16 0->0",          x"00000000", '0', false);
        alu_opa <= x"80000000";
        check_res("SHLR16 80000000",     x"00008000", '0', false);

        -----------------------------------------------------------------------
        --  SWAP.B  {Rm[31:16], Rm[7:0], Rm[15:8]} -> Rn  T unchanged
        --  res_sel=SwapB  t=HOLD  (SwapB unit; upper 16 bits preserved)
        -----------------------------------------------------------------------
        report ">>> SWAP.B" severity note;
        res_sel <= ResSel_SwapB;
        t_sel   <= TCmd_HOLD;

        alu_opa <= x"12345678"; c_in <= '0';   -- lower word: 5678 -> 7856
        check_res("SWAP.B 12345678",     x"12347856", '0', false);
        alu_opa <= x"00000102";                 -- 0102 -> 0201
        check_res("SWAP.B 00000102",     x"00000201", '0', false);
        alu_opa <= x"ABCD0000";                 -- lower word all-0, upper preserved
        check_res("SWAP.B ABCD0000",     x"ABCD0000", '0', false);
        alu_opa <= x"000000FF";
        check_res("SWAP.B 000000FF",     x"0000FF00", '0', false);
        alu_opa <= x"0000FF00";
        check_res("SWAP.B 0000FF00",     x"000000FF", '0', false);
        alu_opa <= x"FFFFABCD";
        check_res("SWAP.B FFFFABCD",     x"FFFFCDAB", '0', false);
        alu_opa <= x"00000000";
        check_res("SWAP.B 0->0",         x"00000000", '0', false);
        alu_opa <= x"DEADBEEF";                 -- upper word DEAD preserved
        check_res("SWAP.B DEADBEEF",     x"DEADEFBE", '0', false);

        -----------------------------------------------------------------------
        --  SWAP.W  {Rm[15:0], Rm[31:16]} -> Rn  T unchanged
        --  s=SWAP  alu=SHIFT  res_sel=ALU  t=HOLD
        -----------------------------------------------------------------------
        report ">>> SWAP.W" severity note;
        s_cmd   <= SCmd_SWAP;
        alu_cmd <= ALUCmd_SHIFT;
        res_sel <= ResSel_ALU;
        t_sel   <= TCmd_HOLD;

        alu_opa <= x"12345678"; c_in <= '0';
        check_res("SWAP.W 12345678",     x"56781234", '0', false);
        alu_opa <= x"00000000";
        check_res("SWAP.W 0->0",         x"00000000", '0', false);
        alu_opa <= x"FFFF0000";
        check_res("SWAP.W FFFF0000",     x"0000FFFF", '0', false);
        alu_opa <= x"0000FFFF";
        check_res("SWAP.W 0000FFFF",     x"FFFF0000", '0', false);
        alu_opa <= x"DEADBEEF";
        check_res("SWAP.W DEADBEEF",     x"BEEFDEAD", '0', false);
        alu_opa <= x"AAAABBBB";
        check_res("SWAP.W AAAABBBB",     x"BBBBAAAA", '0', false);
        alu_opa <= x"00010000";
        check_res("SWAP.W 00010000",     x"00000001", '0', false);

        -----------------------------------------------------------------------
        --  EXTS.B  sign-extend byte -> Rn  T unchanged
        --  ExtendSel="00"  res_sel=Extend  t=HOLD
        -----------------------------------------------------------------------
        report ">>> EXTS.B" severity note;
        extend_sel <= "00";
        res_sel    <= ResSel_Extend;
        t_sel      <= TCmd_HOLD;

        alu_opa <= x"00000055"; c_in <= '0';   -- bit7=0, no sign ext
        check_res("EXTS.B 55",           x"00000055", '0', false);
        alu_opa <= x"000000AA";                 -- bit7=1, sign extend
        check_res("EXTS.B AA",           x"FFFFFFAA", '0', false);
        alu_opa <= x"0000007F";                 -- max positive byte
        check_res("EXTS.B 7F",           x"0000007F", '0', false);
        alu_opa <= x"00000080";                 -- min negative byte
        check_res("EXTS.B 80",           x"FFFFFF80", '0', false);
        alu_opa <= x"00000000";
        check_res("EXTS.B 00",           x"00000000", '0', false);
        alu_opa <= x"000000FF";                 -- -1 as byte
        check_res("EXTS.B FF",           x"FFFFFFFF", '0', false);
        alu_opa <= x"12345678";                 -- only low byte used: 78, bit7=0
        check_res("EXTS.B 78",           x"00000078", '0', false);
        alu_opa <= x"123456FF";                 -- only low byte used: FF
        check_res("EXTS.B upper ignored",x"FFFFFFFF", '0', false);

        -----------------------------------------------------------------------
        --  EXTS.W  sign-extend word -> Rn  T unchanged
        --  ExtendSel="01"  res_sel=Extend  t=HOLD
        -----------------------------------------------------------------------
        report ">>> EXTS.W" severity note;
        extend_sel <= "01";

        alu_opa <= x"00007FFF"; c_in <= '0';   -- bit15=0, no sign ext
        check_res("EXTS.W 7FFF",         x"00007FFF", '0', false);
        alu_opa <= x"00008000";                 -- bit15=1, sign extend
        check_res("EXTS.W 8000",         x"FFFF8000", '0', false);
        alu_opa <= x"0000FFFF";                 -- -1 as word
        check_res("EXTS.W FFFF",         x"FFFFFFFF", '0', false);
        alu_opa <= x"00000000";
        check_res("EXTS.W 0000",         x"00000000", '0', false);
        alu_opa <= x"12345678";                 -- only low word used: 5678, bit15=0
        check_res("EXTS.W 5678",         x"00005678", '0', false);
        alu_opa <= x"1234DEAD";                 -- only low word used: DEAD, bit15=1
        check_res("EXTS.W DEAD",         x"FFFFDEAD", '0', false);

        -----------------------------------------------------------------------
        --  EXTU.B  zero-extend byte -> Rn  T unchanged
        --  ExtendSel="10"  res_sel=Extend  t=HOLD
        -----------------------------------------------------------------------
        report ">>> EXTU.B" severity note;
        extend_sel <= "10";

        alu_opa <= x"000000FF"; c_in <= '0';
        check_res("EXTU.B FF",           x"000000FF", '0', false);
        alu_opa <= x"00000080";
        check_res("EXTU.B 80",           x"00000080", '0', false);
        alu_opa <= x"00000000";
        check_res("EXTU.B 00",           x"00000000", '0', false);
        alu_opa <= x"12345678";                 -- upper bits zeroed
        check_res("EXTU.B 78",           x"00000078", '0', false);
        alu_opa <= x"FFFFFF80";                 -- upper bits zeroed despite all-1
        check_res("EXTU.B upper zeroed", x"00000080", '0', false);

        -----------------------------------------------------------------------
        --  EXTU.W  zero-extend word -> Rn  T unchanged
        --  ExtendSel="11"  res_sel=Extend  t=HOLD
        -----------------------------------------------------------------------
        report ">>> EXTU.W" severity note;
        extend_sel <= "11";

        alu_opa <= x"0000FFFF"; c_in <= '0';
        check_res("EXTU.W FFFF",         x"0000FFFF", '0', false);
        alu_opa <= x"00008000";
        check_res("EXTU.W 8000",         x"00008000", '0', false);
        alu_opa <= x"00000000";
        check_res("EXTU.W 0000",         x"00000000", '0', false);
        alu_opa <= x"12345678";                 -- upper word zeroed
        check_res("EXTU.W 5678",         x"00005678", '0', false);
        alu_opa <= x"FFFF0000";                 -- lower word all-0
        check_res("EXTU.W FFFF0000",     x"00000000", '0', false);
        alu_opa <= x"DEADBEEF";                 -- upper word zeroed
        check_res("EXTU.W BEEF",         x"0000BEEF", '0', false);

        -----------------------------------------------------------------------
        --  XTRCT  {Rn[15:0], Rm[31:16]} -> Rn  T unchanged
        --  opa=Rn  opb=Rm  res_sel=Xtrct  t=HOLD
        --  result[31:16] = opa[15:0],  result[15:0] = opb[31:16]
        -----------------------------------------------------------------------
        report ">>> XTRCT" severity note;
        res_sel <= ResSel_Xtrct;
        t_sel   <= TCmd_HOLD;

        alu_opa <= x"12345678"; alu_opb <= x"ABCDEF00"; c_in <= '0';
        -- {5678, ABCD} = 0x5678ABCD
        check_res("XTRCT 12345678/ABCDEF00", x"5678ABCD", '0', false);
        alu_opa <= x"00000000"; alu_opb <= x"00000000";
        check_res("XTRCT 0/0",              x"00000000", '0', false);
        alu_opa <= x"FFFF0000"; alu_opb <= x"0000FFFF";
        -- {0000, 0000} = 0x00000000
        check_res("XTRCT FFFF0000/0000FFFF",x"00000000", '0', false);
        alu_opa <= x"0000FFFF"; alu_opb <= x"FFFF0000";
        -- {FFFF, FFFF} = 0xFFFFFFFF
        check_res("XTRCT 0000FFFF/FFFF0000",x"FFFFFFFF", '0', false);
        alu_opa <= x"DEADBEEF"; alu_opb <= x"12345678";
        -- {BEEF, 1234} = 0xBEEF1234
        check_res("XTRCT DEADBEEF/12345678",x"BEEF1234", '0', false);
        alu_opa <= x"00001234"; alu_opb <= x"56780000";
        -- {1234, 5678} = 0x12345678
        check_res("XTRCT 00001234/56780000",x"12345678", '0', false);
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"FFFFFFFF";
        check_res("XTRCT all-1/all-1",      x"FFFFFFFF", '0', false);
        alu_opa <= x"00000000"; alu_opb <= x"FFFFFFFF";
        -- {0000, FFFF} = 0x0000FFFF
        check_res("XTRCT 0/all-1",          x"0000FFFF", '0', false);
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"00000000";
        -- {FFFF, 0000} = 0xFFFF0000
        check_res("XTRCT all-1/0",          x"FFFF0000", '0', false);

        -----------------------------------------------------------------------
        -- =================================================================
        --  T-BIT HOLD  — verify T is truly unchanged across representative ops
        -- =================================================================
        -----------------------------------------------------------------------
        report ">>> T-BIT HOLD checks" severity note;

        t_sel    <= TCmd_ONE;
        wait for TPROP;
        -- reset t bit to one before starting

        -- ADD with T=1 held
        f_cmd    <= FCmd_PASSB;
        c_in_cmd <= CinCmd_ZERO;
        alu_cmd  <= ALUCmd_ADDER;
        res_sel  <= ResSel_ALU;
        t_sel    <= TCmd_HOLD;
        alu_opa <= x"FFFFFFFF"; alu_opb <= x"00000001"; c_in <= '1';
        wait for TPROP;
        n_tests.increment;
        if t_bit /= '1' then
            report "[FAIL] T-HOLD ADD carry T=1" severity error; n_fail.increment;
        else
            report "[PASS] T-HOLD ADD carry T=1" severity note;
        end if;

        -- SHLL2 with T=1 held
        s_cmd    <= SCmd_LSL;
        c_in_cmd <= CinCmd_ZERO;
        alu_cmd  <= ALUCmd_SHIFT;
        res_sel  <= ResSel_Shift2;
        c_in     <= '1';
        alu_opa  <= x"80000000";    -- would set T if SHLL, but SHLL2 holds T
        wait for TPROP;
        n_tests.increment;
        if t_bit /= '1' then
            report "[FAIL] T-HOLD SHLL2 T=1" severity error; n_fail.increment;
        else
            report "[PASS] T-HOLD SHLL2 T=1" severity note;
        end if;
        c_in <= '0';

        t_sel    <= TCmd_ZERO;
        wait for TPROP;
        -- reset t bit to zero before starting

        -- AND with T=0 held
        f_cmd   <= FCmd_AND;
        alu_cmd <= ALUCmd_FBLOCK;
        c_in    <= '0';
        alu_opa <= x"A5A5A5A5"; alu_opb <= x"5A5A5A5A";
        wait for TPROP;
        n_tests.increment;
        if t_bit /= '0' then
            report "[FAIL] T-HOLD AND complement T=0" severity error; n_fail.increment;
        else
            report "[PASS] T-HOLD AND complement T=0" severity note;
        end if;


        -----------------------------------------------------------------------
        -- =================================================================
        --  SUMMARY
        -- =================================================================
        -----------------------------------------------------------------------
        report "=== SUMMARY: "
             & integer'image(n_tests.get) & " tests, "
             & integer'image(n_fail.get)  & " failures ==="
             severity note;

        if n_fail.get = 0 then
            report "ALL TESTS PASSED" severity note;
        else
            report integer'image(n_fail.get) & " TEST(S) FAILED"
                severity failure;
        end if;

        wait; -- suspend forever
    end process stim;

end architecture Behavioral;