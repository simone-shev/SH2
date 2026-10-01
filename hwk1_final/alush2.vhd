----------------------------------------------------------------------------
--
--  SH-2 ALU
--
--  This is an implementation of an ALU for the SH-2 it uses the 
--  generic ALU. The ALU implements an F block, adder and shifter and MUX 
--  between all results. Multiply/Divide instructions and MAC instructions are
--  not implemented. Shift instructions by 2, 6, and 8 are implemented. Swap
--  byte instructions, sign and zero extension instructions, and extract 
--  instructions are also implemented. 
--
--  Packages included are:
--     TConstants - constants for how the Tbit should be set based on the instruction
--
--  Entities included are:
--     ShiftN  - Shift and rotate by N bits (generic shiftamt)
--     SwapB   - swap bytes 0 and 1 with bytes 2 and 3
--     Extend   - sign and zero extension by byte or word
--     ALUSH2  - the ALU for SH2
--
--  Revision History:
--     7 Apr 26  Simone Shevchuk       Initial revision.
--     9 Apr 26  Simone Shevchuk       Added Tbit Zero and one set, update XNOR
--     15 Apr 26 Simone Shevchuk       Changed from 3 shifters to ShiftN, add Swap, Sign extension, and extract
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

-- Tbit command constants, used to select which value to set the Tbit to based on the instruction
package  TConstants  is
   constant TCmd_HOLD       : std_logic_vector(3 downto 0) := "0000"; 
   constant TCmd_C          : std_logic_vector(3 downto 0) := "0001"; -- carry
   constant TCmd_V          : std_logic_vector(3 downto 0) := "0010"; -- overflow
   constant TCmd_Z          : std_logic_vector(3 downto 0) := "0011"; -- zero
   constant TCmd_S          : std_logic_vector(3 downto 0) := "0100"; -- sign
   constant TCmd_CNZ        : std_logic_vector(3 downto 0) := "0101"; -- carry and not zero
   constant TCmd_SXNORV     : std_logic_vector(3 downto 0) := "0110"; -- not (sign xor overflow)
   constant TCmd_SXNORVNZ   : std_logic_vector(3 downto 0) := "0111"; -- not (sign xor overflow) and not zero
   constant TCmd_NSNZ       : std_logic_vector(3 downto 0) := "1000"; -- not (negative or zero)
   constant TCmd_NS         : std_logic_vector(3 downto 0) := "1001"; -- not sign
   constant TCmd_LSB        : std_logic_vector(3 downto 0) := "1010"; -- least significant bit of the result
   constant TCmd_CMPSTR     : std_logic_vector(3 downto 0) := "1011"; -- result of compare str instruction, set to 1 if any byte of the result is 0, otherwise 0
   constant TCmd_NC         : std_logic_vector(3 downto 0) := "1100"; -- not carry
   constant TCmd_ZERO       : std_logic_vector(3 downto 0) := "1101"; -- set to 0, override other settings
   constant TCmd_ONE        : std_logic_vector(3 downto 0) := "1110"; -- set to 1, override other settings

end package;

--
--  ShiftN
--
--  Shifter for doing shift/rotate operations by N in {2, 8, 16} bits in the ALU.
--  The determination of shift amount is given by an input ShiftSel, and the 
--  type of shift (only relevent as left or right) is given by SCmd.
--
--
--  Inputs:
--    SOp      - operand
--    ShiftSel - shift to apply to offset, 0 for shift of 2, 1 for shift of 8, 2 for shift of 16
--    SCmd     - operation to perform (3 bits, SCmd_LEFT / SCmd_RIGHT)
--
--  Outputs:
--    SResult - shift result
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.std_match;
use work.ALUConstants.all;

entity ShiftN is
    port (
        SOp      : in  std_logic_vector(31 downto 0);
        SCmd     : in  std_logic_vector(2 downto 0); -- same encoding as the SCmd for shifts in the generic ALU, but only LEFT and RIGHT are relevant
        ShiftSel : in  integer range 2 downto 0;  -- 0 to 2, 1 to 8, 2 to 16
        SResult  : out std_logic_vector(31 downto 0)
    );
end ShiftN;

architecture dataflow of ShiftN is
begin
    -- use concatenation and slicing to implement the shifts/rotates by the appropriate amount based on the command and select signal
    SResult <=
        b"00"                    & SOp(31 downto 2)   when ShiftSel=0 and std_match(SCmd,SCmd_RIGHT) else
        SOp(29 downto 0)         & b"00"              when ShiftSel=0 and std_match(SCmd,SCmd_LEFT)  else
        b"00000000"              & SOp(31 downto 8)   when ShiftSel=1 and std_match(SCmd,SCmd_RIGHT) else
        SOp(23 downto 0)         & b"00000000"        when ShiftSel=1 and std_match(SCmd,SCmd_LEFT)  else
        x"0000"                  & SOp(31 downto 16)  when ShiftSel=2 and std_match(SCmd,SCmd_RIGHT) else
        SOp(15 downto 0)         & x"0000"            when ShiftSel=2 and std_match(SCmd,SCmd_LEFT)  else
        (others => 'X');
end dataflow;


--
--  SwapB
--
--  This is the swapper for doing byte swap operations in the ALU. Unlike the swap operation
--  in the generic ALU, this only swaps bytes 0 and 1 with bytes 2 and 3, it does 
--  not swap other bytes/whole words.
--
--
--  Inputs:
--    SOp     - operand
--
--  Outputs:
--    SResult - swap result
--

library ieee;
use ieee.std_logic_1164.all;

entity  SwapB  is

    port(
        SOp     : in   std_logic_vector(31 downto 0); -- operand
        SResult : out  std_logic_vector(31 downto 0) -- swap result
    );

end  SwapB;


architecture  dataflow  of  SwapB  is
begin

    -- swap bytes 0 and 1 of the low word; upper word is preserved unchanged
    SResult(7 downto 0)   <= SOp(15 downto 8);
    SResult(15 downto 8)  <= SOp(7 downto 0);
    SResult(31 downto 16) <= SOp(31 downto 16);

end  dataflow;

--
--  Extend
--
--  This is the extender for doing sign or zero extension operations in the ALU. 
--  The extension is defined with an input for the type of extension to perform. 
--  This can be sign extending by byte or by word, or zero extending by byte or by word.
--
--
--  Inputs:
--    SOp       - operand
--    ExtendSel - extension command (2 bits)
--
--  Outputs:
--    SResult - swap result
--

library ieee;
use ieee.std_logic_1164.all;

entity  Extend  is
    port(
        SOp       : in   std_logic_vector(31 downto 0);       -- operand
        ExtendSel : in   std_logic_vector(1 downto 0);        -- extension command 
        -- (00 for sign extend byte, 01 for sign extend word, 10 for zero extend byte, 11 for zero extend word)
        EResult   : out  std_logic_vector(31 downto 0)        -- extension result
    );

end  Extend;


architecture  dataflow  of  Extend  is
begin

    -- for sign extension, if the high bit of the byte/word is 1, set the upper bits to 1, otherwise set to 0
    EResult <= (31 downto 8 => SOp(7))      &   SOp(7 downto 0)     when ExtendSel = "00" else
               (31 downto 16 => SOp(15))    &   SOp(15 downto 0)   when ExtendSel = "01" else
               (31 downto 8 => '0')         &   SOp(7 downto 0)     when ExtendSel = "10" else
               (31 downto 16 => '0')        &   SOp(15 downto 0)   when ExtendSel = "11" else
               (others => '0'); -- for zero extension just set upper bits to 0

end  dataflow;


--
--  ALUSH2
--
--  This is an ALU for SH2. The SH-2 ALU uses the generic ALU implementation 
--  This generates appropriate signals from the control signals and creates a
--  shifter, swapper and etender to calculate the result of instructions that
--  are not covered by the generic ALU (SWAP.B, SHLLN, EXTU). The final result 
--  muxes between the generic ALU result, shifter, swapper, extender and extract 
--  based on the command. The Tbit is set based on the command to either be the 
--  carry out from the operation, the overflow, the zero result, the sign result, 
--  or some combination of these.
--  
--
--  Inputs:
--    alu_opa   - first operand
--    alu_opb   - second operand
--    c_in      - carry in (from tbit)
--    f_cmd     - f-block operation to perform (4 bits)
--    c_in_cmd  - adder carry in operation for carry in (2 bits)
--    s_cmd     - shift operation to perform (3 bits)
--    alu_cmd   - alu operation to perform - selects result (2 bits)
--    shift_sel - shift amount selection for shift by N unit (0 for shift by 2, 1 for shift by 8, 2 for shift by 16)
--    extend_sel- extension operation selection for extender unit (2 bits)
--    res_sel   - selects between alu result, shift by N result, swap result, extend result, and extract result
--    t_sel     - select for how the tbit should be set
--
--  Outputs:
--    res       - ALUSH2 result
--    t_bit     - Tbit ouptut as one of the constants above

library ieee;
use ieee.std_logic_1164.all;
use work.ALUConstants.all;
use work.TConstants.all;

entity  ALUSH2  is

    port(
        alu_opa  : in      std_logic_vector(31 downto 0);   -- first operand
        alu_opb  : in      std_logic_vector(31 downto 0);   -- second operand
        c_in     : in      std_logic;                       -- carry in
        f_cmd    : in      std_logic_vector(3 downto 0);    -- F-Block operation
        c_in_cmd : in      std_logic_vector(1 downto 0);    -- carry in operation
        s_cmd    : in      std_logic_vector(2 downto 0);    -- shift operation
        alu_cmd  : in      std_logic_vector(1 downto 0);    -- Generic ALU result select
        shift_sel : in     integer range 2 downto 0;        -- shift amount selection
        extend_sel : in   std_logic_vector(1 downto 0);     -- extension operation selection
        res_sel  : in      integer range 4 downto 0;        -- select between shiftN, swap, extend, extract and ALU result
        t_sel    : in      std_logic_vector(3 downto 0);    -- select for the Tbit
        res      : buffer  std_logic_vector(31 downto 0);   -- ALUSH2 result
        t_bit    : buffer     std_logic                     -- Tbit output, see constants above
    );

end  ALUSH2;


architecture  structural  of  ALUSH2  is

    signal  GenALURes       : std_logic_vector(31 downto 0);    -- generic ALU result
    signal  ShiftNRes       : std_logic_vector(31 downto 0);    -- shift-by-N result
    signal  swap            : std_logic_vector(31 downto 0);    -- swap result
    signal  extend          : std_logic_vector(31 downto 0);    -- extend result
    signal  extract         : std_logic_vector(31 downto 0);    -- extract result

    signal  c_out           : std_logic;                        -- carry out from the operation, used for Tbit 
    signal  overflow_res    : std_logic;                        -- overflow from the operation, used for Tbit
    signal  zero_res        : std_logic;                        -- result of comparison is value 0, used for Tbit
    signal  sign_res        : std_logic;                        -- result of comparison is negative, used for Tbit
    signal  cmp_str_res     : std_logic;                        -- result of compare str instruction, used for Tbit

begin
    -- instantiate the generic ALU
    ALUGeneric: entity work.ALU
        generic map (
            wordsize => 32    -- 32-bit wide
        )

        port map (
            ALUOpA   => alu_opa, 
            ALUOpB   => alu_opb, 
            Cin      => c_in, 
            FCmd     => f_cmd, 
            CinCmd   => c_in_cmd, 
            SCmd     => s_cmd, 
            ALUCmd   => alu_cmd,
            Result   => GenALURes,
            Cout     => c_out,
            HalfCout => open,
            Overflow => overflow_res,
            Zero     => zero_res,                                 
            Sign     => sign_res
        );

    -- instantiate the shift-by-N units using ShiftN
    ShiftNUnit: entity work.ShiftN
        port map (
            SOp => alu_opa, 
            ShiftSel => shift_sel,
            SCmd => s_cmd,
            SResult => ShiftNRes
        );
    
    -- instantiate the swap unit
    SwapUnit: entity work.SwapB
        port map (
            SOp => alu_opa,
            SResult => swap
        );

    -- instantiate the extend unit
    ExtendUnit: entity work.Extend
        port map (
            SOp => alu_opa,
            ExtendSel => extend_sel,
            EResult => extend
        );

    -- for extract, the upper half is bits 15-0 of operand A and the lower half is bits 7-0 of operand B
    extract(31 downto 16) <= alu_opa(15 downto 0);
    extract(15 downto 0) <= alu_opb(31 downto 16);

    -- mux between the different results based on the command to produce the final result
    res <=  ShiftNRes   when (res_sel = 1) else
            swap        when (res_sel = 2) else
            extend      when (res_sel = 3) else
            extract     when (res_sel = 4) else
            GenALURes;

    -- for CMPSTR set to 1 if any byte of the result is 0, otherwise 0
    cmp_str_res <=  '1'  when (res(31 downto 24) = x"00") or
                              (res(23 downto 16) = x"00") or
                              (res(15 downto  8) = x"00") or
                              (res( 7 downto  0) = x"00")
                         else '0';

    -- set the Tbit based on the command, using the constants defined above 
    t_bit <= t_bit                                              when (t_sel = TCmd_HOLD)        else
             c_out                                              when (t_sel = TCmd_C)           else
             overflow_res                                       when (t_sel = TCmd_V)           else
             zero_res                                           when (t_sel = TCmd_Z)           else
             sign_res                                           when (t_sel = TCmd_S)           else
             (c_out and not(zero_res))                          when (t_sel = TCmd_CNZ)         else
             not (sign_res xor overflow_res)                    when (t_sel = TCmd_SXNORV)      else
             (not (sign_res xor overflow_res) and not(zero_res))when (t_sel = TCmd_SXNORVNZ)    else
             (not sign_res) and (not zero_res)                  when (t_sel = TCmd_NSNZ)        else
             not sign_res                                       when (t_sel = TCmd_NS)          else
             res(0)                                             when (t_sel = TCmd_LSB)         else 
             cmp_str_res                                        when (t_sel = TCmd_CMPSTR)      else
             not c_out                                          when (t_sel = TCmd_NC)          else
             '0'                                                when (t_sel = TCmd_ZERO)        else
             '1'                                                when (t_sel = TCmd_ONE)         else
             'X'; -- anything else is illegal
end  structural;