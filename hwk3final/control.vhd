----------------------------------------------------------------------------
--
--  SH-2 Control Unit
--
--  This is an implementation of the control unit for the SH-2 it contains a
--  state machine to control the execution of instructions and generate the
--  appropriate control signals for the other blocks, the ALU, PAU, DAU, and
--  the register array. It also contains the logic to handle interrupts and
--  exceptions.
--
--  In the pipelined version, the control unit serves the ID stage. It keeps
--  the IR latch (IF/ID pipeline register) internally and combinationally
--  decodes all control signals in a single cycle. Multi-cycle instruction
--  timing (cycleCnt) is removed; pipeline stages handle the sequencing.
--  The Tbit input is removed since branch condition evaluation moves to EX.
--
--  Entities included are:
--     ControlSH2  - the control unit
--
--  Revision History:
--     20 Apr 26  Simone Shevchuk       Initial revision.
--     26 Apr 26  Simone Shevchuk       Add control signals for all instructions, add default values for signals, no FSM
--     28 Apr 26  Simone Shevchuk       reg_ax_in removed
--     29 Apr 26  Simone Shevchuk       Add clock handling for memory access/write
--     01 May 26  Simone Shevchuk       Double instruction fetch mux IR
--     03 May 26  Simone Shevchuk       Update DAU controls for MOV instructions
--     05 May 26  Simone Shevchuk       Add imm_sel control signal for selecting type of immediate value and add control signals for NEG/NEGC
--     08 Apr 26  Simone Shevchuk       Add delay slot handling, add comments
--     11 May 26  Simone Shevchuk       Change register select in byte word MOV for register indirect
--     12 May 26  Simone Shevchuk       Add alu_opb_bit7 output for TAS.B bit 7 set
--     12 May 26  Simone Shevchuk       Fix STC.L GBR/VBR src_sel, add dau_load_data
--     17 May 26  Simone Shevchuk       Flatten all multi-cycle decodes to single-cycle,
--                                      remove cycleCnt/last_cycle/delay_slot_reg/addr_bus_sel,
--                                      remove Tbit input (branch decisions move to EX),
--                                      add stall_IF/flush_IF inputs and id_valid output,
--                                      add is_mem/is_load/is_rmw/is_branch/is_cond_branch/
--                                      is_BT/is_BF decode outputs, change RE default to RE_NONE.
--
----------------------------------------------------------------------------


--
--  ControlSH2
--
--  This is the control unit for the SH-2 pipeline ID stage. It contains the
--  IR latch (IF/ID pipeline register) and a combinational decode process that
--  generates one set of control signals per instruction per cycle.
--
--  The stall_IF input freezes IR and id_valid (pipeline stall from structural
--  hazard or load-use detection). The flush_IF input invalidates the current
--  fetch (branch redirect squashes the in-flight instruction).
--
--  Inputs:
--    DB            - value coming in from the DB (instruction fetch data)
--    addr_bit1     - bit 1 of the address for half-word selection into IR
--    clock         - the system clock
--    reset         - reset signal (active low)
--    stall_IF      - when '1', hold IR and id_valid unchanged
--    flush_IF      - when '1', clear id_valid (squash fetched instruction)
--
--  Outputs:
--    IR              - the latched instruction register (readable by sh2cpue for immediate extraction)
--    id_valid        - valid bit for the IF/ID pipeline register
--    reg_ALU_IN      - register write controls [3(src) + 4(sel) + 1(store)]
--    reg_MAU         - register read selects [4(a) + 4(b) + 4(ax) + 1(ax_store) + 4(a2)]
--    alu_IN          - ALU source selection [1(sel_a) + 1(sel_b)]
--    alu_gen         - generic ALU controls [4(f) + 2(cin) + 3(s) + 2(cmd)]
--    alu_sh2         - SH2 ALU controls [2(shift) + 2(extend) + 3(res) + 4(t)]
--    dau_controls    - DAU address computation controls
--    dau_write       - GBR/VBR write enables
--    dau_out_sel     - DAU output mux select
--    pau_controls    - PAU branch controls [2(src) + 2(offset) + 2(pr_sel)]
--    RE              - data read enables for MEM stage (RE_NONE for non-memory instructions)
--    WE              - data write enables for MEM stage
--    delay_slot      - '1' if this branch has a delay slot (rides through pipeline)
--    data_bus_sel    - data bus source for stores (ALU/DAU/SR/PR)
--    sign_zero_ALU_sel - sign/zero extend select for ALU immediate input
--    tbit_write      - T-bit write enable
--    imm_sel         - immediate type [00=8b sign, 01=4b zero, 10=12b sign, 11=8b zero]
--    alu_opa_zero    - force ALU operand A to zero
--    alu_opa_hold    - use db_hold as ALU operand A (for RMW in MEM stage)
--    alu_opb_bit7    - force ALU operand B to 0x80 (TAS.B)
--    dau_load_data   - select memory data for GBR/VBR write source in WB
--    is_mem          - instruction needs data memory access in MEM stage
--    is_load         - instruction loads from memory to register
--    is_rmw          - instruction is read-modify-write (multi-cycle in MEM)
--    is_branch       - instruction is a branch/jump
--    is_cond_branch  - branch is conditional (depends on T-bit)
--    is_BT           - conditional branch is BT or BT/S
--    is_BF           - conditional branch is BF or BF/S

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.std_match;
use work.InstructionConstants.all;

entity  ControlSH2  is

    port(
        DB              : in   std_logic_vector(31 downto 0);
        addr_bit1       : in   std_logic;
        clock           : in   std_logic;
        reset           : in   std_logic;
        stall_IF        : in   std_logic;
        flush_IF        : in   std_logic;
        IR              : buffer  std_logic_vector(15 downto 0);
        id_valid        : buffer  std_logic;
        reg_ALU_IN      : out  std_logic_vector(7 downto 0);
        reg_MAU         : out  std_logic_vector(16 downto 0);
        alu_IN          : out  std_logic_vector(1 downto 0);
        alu_gen         : out  std_logic_vector(10 downto 0);
        alu_sh2         : out  std_logic_vector(10 downto 0);
        dau_controls    : out  std_logic_vector(9 downto 0);
        dau_write       : out  std_logic_vector(1 downto 0);
        dau_out_sel     : out  std_logic_vector(1 downto 0);
        pau_controls    : out  std_logic_vector(5 downto 0);
        RE              : out  std_logic_vector(3 downto 0);
        WE              : out  std_logic_vector(3 downto 0);
        delay_slot      : out  std_logic;
        data_bus_sel    : out  std_logic_vector(1 downto 0);
        sign_zero_ALU_sel : out  std_logic;
        tbit_write      : out  std_logic;
        imm_sel         : out  std_logic_vector(1 downto 0);
        alu_opa_zero    : out  std_logic;
        alu_opa_hold    : out  std_logic;
        alu_opb_bit7    : out  std_logic;
        dau_load_data   : out  std_logic;
        is_mem          : out  std_logic;
        is_load         : out  std_logic;
        is_rmw          : out  std_logic;
        is_branch       : out  std_logic;
        is_cond_branch  : out  std_logic;
        is_BT           : out  std_logic;
        is_BF           : out  std_logic
    );

end  ControlSH2;


architecture  structural  of  ControlSH2  is
    alias mreg : std_logic_vector(3 downto 0) is IR(7 downto 4);
    alias nreg : std_logic_vector(3 downto 0) is IR(11 downto 8);
begin

    -- IR latch with stall/flush pipeline control
    process(clock)
    begin
        if rising_edge(clock) then
            if reset = '0' then
                IR <= (others => '0');
                id_valid <= '0';
            elsif stall_IF = '1' then
                null; -- hold IR and id_valid unchanged
            elsif flush_IF = '1' then
                id_valid <= '0';
            else
                if addr_bit1 = '0' then
                    IR <= DB(31 downto 16);
                else
                    IR <= DB(15 downto 0);
                end if;
                id_valid <= '1';
            end if;
        end if;
    end process;

    -- Combinational decode generates all control signals from current IR
    -- in a single cycle. 
    process(all)
    begin

        -- Defaults — overridden only where an instruction needs a different value
        reg_ALU_IN        <= REG_IN_NONE;
        reg_MAU           <= REG_MAU_NONE;
        alu_IN            <= ALU_IN_DATAREG;
        alu_gen           <= ALU_GEN_PASS;
        dau_out_sel       <= "00";
        data_bus_sel      <= "00";
        dau_controls      <= DAU_CTRL_NONE;
        dau_write         <= DAU_WRITE_NONE;
        alu_sh2           <= ALU_SH2_NONE;
        pau_controls      <= PAU_SEQ;
        RE                <= RE_NONE;  -- no data read (instruction fetch handled separately)
        WE                <= WE_NONE;
        delay_slot        <= '0';
        sign_zero_ALU_sel <= '0';
        tbit_write        <= '0';
        imm_sel           <= "00";
        alu_opa_zero      <= '0';
        alu_opa_hold      <= '0';
        alu_opb_bit7      <= '0';
        dau_load_data     <= '0';
        is_mem            <= '0';
        is_load           <= '0';
        is_rmw            <= '0';
        is_branch         <= '0';
        is_cond_branch    <= '0';
        is_BT             <= '0';
        is_BF             <= '0';

        if   std_match(IR, RESET_VECTOR_AT_0) then
            pau_controls         <= PAU_HOLD;


        elsif     std_match(IR, MOV_IMM_IMM_RN) then  -- MOV #imm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            alu_IN               <= ALU_IN_DATAIMM;
            alu_gen              <= ALU_GEN_IMM;
            sign_zero_ALU_sel    <= '1';

        elsif  std_match(IR, MOV_RM_RN) then  -- MOV Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (mreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;

        elsif  std_match(IR, MOV_W_AT_DISP_PC_RN) then  -- MOV.W @(disp,PC),Rn
            imm_sel              <= "11";
            reg_ALU_IN           <= ("001" & nreg & "1");
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_IMM;
            dau_controls         <= "1101000000";
            RE                   <= RE_WORD;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_L_AT_DISP_PC_RN) then  -- MOV.L @(disp,PC),Rn
            imm_sel              <= "11";
            reg_ALU_IN           <= ("001" & nreg & "1");
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_IMM;
            dau_controls         <= "1110000000";
            RE                   <= RE_LONG;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_B_RM_AT_RN) then  -- MOV.B Rm,@Rn
            reg_MAU              <= (mreg & "000000000" & nreg);
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            WE                   <= WE_BYTE;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_W_RM_AT_RN) then  -- MOV.W Rm,@Rn
            reg_MAU              <= (mreg & "000000000" & nreg);
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            WE                   <= WE_WORD;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_L_RM_AT_RN) then  -- MOV.L Rm,@Rn
            reg_MAU              <= (mreg & "000000000" & nreg);
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            WE                   <= WE_LONG;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_B_AT_RM_RN) then  -- MOV.B @Rm,Rn
            reg_ALU_IN           <= ("001" & nreg & "1");
            reg_MAU              <= ("0000000000000" & mreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            RE                   <= RE_BYTE;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_W_AT_RM_RN) then  -- MOV.W @Rm,Rn
            reg_ALU_IN           <= ("001" & nreg & "1");
            reg_MAU              <= ("0000000000000" & mreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            RE                   <= RE_WORD;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_L_AT_RM_RN) then  -- MOV.L @Rm,Rn
            reg_ALU_IN           <= ("001" & nreg & "1");
            reg_MAU              <= ("0000000000000" & mreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            RE                   <= RE_LONG;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_B_AT_RM_PLUS_RN) then  -- MOV.B @Rm+,Rn
            reg_ALU_IN           <= ("001" & nreg & "1");
            reg_MAU              <= ("00000000" & mreg & "1" & mreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000100000";
            RE                   <= RE_BYTE;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_W_AT_RM_PLUS_RN) then  -- MOV.W @Rm+,Rn
            reg_ALU_IN           <= ("001" & nreg & "1");
            reg_MAU              <= ("00000000" & mreg & "1" & mreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000100010";
            RE                   <= RE_WORD;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_L_AT_RM_PLUS_RN) then  -- MOV.L @Rm+,Rn
            reg_ALU_IN           <= ("001" & nreg & "1");
            reg_MAU              <= ("00000000" & mreg & "1" & mreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_IMM;
            dau_controls         <= "0000100100";
            RE                   <= RE_LONG;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_B_RM_AT_MINUSRN) then  -- MOV.B Rm,@-Rn
            reg_MAU              <= (mreg & "0000" & nreg & "1" & nreg);
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000101001";
            WE                   <= WE_BYTE;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_W_RM_AT_MINUSRN) then  -- MOV.W Rm,@-Rn
            reg_MAU              <= (mreg & "0000" & nreg & "1" & nreg);
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000101011";
            WE                   <= WE_WORD;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_L_RM_AT_MINUSRN) then  -- MOV.L Rm,@-Rn
            reg_MAU              <= (mreg & "0000" & nreg & "1" & nreg);
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000101101";
            WE                   <= WE_LONG;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_B_R0_AT_DISP_RN) then  -- MOV.B R0,@(disp,Rn)
            imm_sel              <= "01";
            reg_MAU              <= ("0000000000000" & IR(7 downto 4));
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= DAU_CTRL_OFFSET_DISP8;
            WE                   <= WE_BYTE;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_W_R0_AT_DISP_RN) then  -- MOV.W R0,@(disp,Rn)
            imm_sel              <= "01";
            reg_MAU              <= ("0000000000000" & IR(7 downto 4));
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0001000000";
            WE                   <= WE_WORD;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_L_RM_AT_DISP_RN) then  -- MOV.L Rm,@(disp,Rn)
            imm_sel              <= "01";
            reg_MAU              <= (mreg & "000000000" & nreg);
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0010000000";
            WE                   <= WE_LONG;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_B_AT_DISP_RM_R0) then  -- MOV.B @(disp,Rm),R0
            imm_sel              <= "01";
            reg_ALU_IN           <= REG_IN_R0_ONLY;
            reg_MAU              <= ("0000000000000" & mreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= DAU_CTRL_OFFSET_DISP8;
            RE                   <= RE_BYTE;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_W_AT_DISP_RM_R0) then  -- MOV.W @(disp,Rm),R0
            imm_sel              <= "01";
            reg_ALU_IN           <= REG_IN_R0_ONLY;
            reg_MAU              <= ("0000000000000" & mreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0001000000";
            RE                   <= RE_WORD;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_L_AT_DISP_RM_RN) then  -- MOV.L @(disp,Rm),Rn
            imm_sel              <= "01";
            reg_ALU_IN           <= ("001" & nreg & "1");
            reg_MAU              <= ("0000000000000" & mreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0010000000";
            RE                   <= RE_LONG;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_B_RM_AT_R0_RN) then  -- MOV.B Rm,@(R0,Rn)
            reg_MAU              <= (mreg & "000000000" & nreg);
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000010000";
            WE                   <= WE_BYTE;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_W_RM_AT_R0_RN) then  -- MOV.W Rm,@(R0,Rn)
            reg_MAU              <= (mreg & "000000000" & nreg);
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000010000";
            WE                   <= WE_WORD;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_L_RM_AT_R0_RN) then  -- MOV.L Rm,@(R0,Rn)
            reg_MAU              <= (mreg & "000000000" & nreg);
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000010000";
            WE                   <= WE_LONG;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_B_AT_R0_RM_RN) then  -- MOV.B @(R0,Rm),Rn
            reg_ALU_IN           <= ("001" & nreg & "1");
            reg_MAU              <= ("0000000000000" & mreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000010000";
            RE                   <= RE_BYTE;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_W_AT_R0_RM_RN) then  -- MOV.W @(R0,Rm),Rn
            reg_ALU_IN           <= ("001" & nreg & "1");
            reg_MAU              <= ("0000000000000" & mreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000010000";
            RE                   <= RE_WORD;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_L_AT_R0_RM_RN) then  -- MOV.L @(R0,Rm),Rn
            reg_ALU_IN           <= ("001" & nreg & "1");
            reg_MAU              <= ("0000000000000" & mreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000010000";
            RE                   <= RE_LONG;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_B_R0_AT_DISP_GBR) then  -- MOV.B R0,@(disp,GBR)
            imm_sel              <= "11";
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0100000000";
            WE                   <= WE_BYTE;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_W_R0_AT_DISP_GBR) then  -- MOV.W R0,@(disp,GBR)
            imm_sel              <= "11";
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0101000000";
            WE                   <= WE_WORD;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_L_R0_AT_DISP_GBR) then  -- MOV.L R0,@(disp,GBR)
            imm_sel              <= "11";
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0110000000";
            WE                   <= WE_LONG;
            is_mem               <= '1';

        elsif  std_match(IR, MOV_B_AT_DISP_GBR_R0) then  -- MOV.B @(disp,GBR),R0
            imm_sel              <= "11";
            reg_ALU_IN           <= REG_IN_R0_ONLY;
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0100000000";
            RE                   <= RE_BYTE;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_W_AT_DISP_GBR_R0) then  -- MOV.W @(disp,GBR),R0
            imm_sel              <= "11";
            reg_ALU_IN           <= REG_IN_R0_ONLY;
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0101000000";
            RE                   <= RE_WORD;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOV_L_AT_DISP_GBR_R0) then  -- MOV.L @(disp,GBR),R0
            imm_sel              <= "11";
            reg_ALU_IN           <= REG_IN_R0_ONLY;
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0110000000";
            RE                   <= RE_LONG;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, MOVA_AT_DISP_PC_R0) then  -- MOVA @(disp,PC),R0
            imm_sel              <= "11";
            reg_ALU_IN           <= "10000001";
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_IMM;
            dau_controls         <= "1110000000";
            dau_out_sel          <= "11";

        elsif  std_match(IR, MOVT_RN) then  -- MOVT Rn
            reg_ALU_IN           <= ("010" & nreg & "1");
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_NONE;

        elsif  std_match(IR, SWAP_B_RM_RN) then  -- SWAP.B Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (mreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            alu_sh2              <= "00000100000";

        elsif  std_match(IR, SWAP_W_RM_RN) then  -- SWAP.W Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (mreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= "11000000110";

        elsif  std_match(IR, XTRCT_RM_RN) then  -- XTRCT Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            alu_sh2              <= "00001000000";

        elsif  std_match(IR, ADD_RM_RN) then  -- ADD Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_ADD;

        elsif  std_match(IR, ADD_IMM_IMM_RN) then  -- ADD #imm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGIMM;
            alu_gen              <= ALU_GEN_ADD;
            sign_zero_ALU_sel    <= '1';

        elsif  std_match(IR, ADDC_RM_RN) then  -- ADDC Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_ADDC;
            alu_sh2              <= "00000000001";
            tbit_write           <= '1';

        elsif  std_match(IR, ADDV_RM_RN) then  -- ADDV Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_ADD;
            alu_sh2              <= "00000000010";
            tbit_write           <= '1';

        elsif  std_match(IR, CMP_EQ_RM_RN) then  -- CMP/EQ Rm,Rn
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SUB;
            alu_sh2              <= "00000000011";
            tbit_write           <= '1';

        elsif  std_match(IR, CMP_EQ_IMM_IMM_R0) then  -- CMP/EQ #imm,R0
            alu_IN               <= ALU_IN_REGIMM;
            alu_gen              <= ALU_GEN_SUB;
            alu_sh2              <= "00000000011";
            sign_zero_ALU_sel    <= '1';
            tbit_write           <= '1';

        elsif  std_match(IR, CMP_GE_RM_RN) then  -- CMP/GE Rm,Rn
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SUB;
            alu_sh2              <= "00000000110";
            tbit_write           <= '1';

        elsif  std_match(IR, CMP_GT_RM_RN) then  -- CMP/GT Rm,Rn
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SUB;
            alu_sh2              <= "00000000111";
            tbit_write           <= '1';

        elsif  std_match(IR, CMP_HI_RM_RN) then  -- CMP/HI Rm,Rn
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SUB;
            alu_sh2              <= "00000000101";
            tbit_write           <= '1';

        elsif  std_match(IR, CMP_HS_RM_RN) then  -- CMP/HS Rm,Rn
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SUB;
            alu_sh2              <= "00000000001";
            tbit_write           <= '1';

        elsif  std_match(IR, CMP_PL_RN) then  -- CMP/PL Rn
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            alu_sh2              <= "00000001000";
            tbit_write           <= '1';

        elsif  std_match(IR, CMP_PZ_RN) then  -- CMP/PZ Rn
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            alu_sh2              <= "00000001001";
            tbit_write           <= '1';

        elsif  std_match(IR, CMP_STR_RM_RN) then  -- CMP/STR Rm,Rn
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_XOR;
            alu_sh2              <= "00000001011";
            tbit_write           <= '1';

        elsif  std_match(IR, EXTS_B_RM_RN) then  -- EXTS.B Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (mreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            alu_sh2              <= "00000110000";

        elsif  std_match(IR, EXTS_W_RM_RN) then  -- EXTS.W Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (mreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            alu_sh2              <= "00010110000";

        elsif  std_match(IR, EXTU_B_RM_RN) then  -- EXTU.B Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (mreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            alu_sh2              <= "00100110000";

        elsif  std_match(IR, EXTU_W_RM_RN) then  -- EXTU.W Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (mreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            alu_sh2              <= "00110110000";

        elsif  std_match(IR, SUB_RM_RN) then  -- SUB Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SUB;

        elsif  std_match(IR, SUBC_RM_RN) then  -- SUBC Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SUBC;
            alu_sh2              <= "00000001100";
            tbit_write           <= '1';

        elsif  std_match(IR, SUBV_RM_RN) then  -- SUBV Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SUBV;
            alu_sh2              <= "00000000010";
            tbit_write           <= '1';

        elsif  std_match(IR, NEG_RM_RN) then  -- NEG Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= ("0000" & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_NEG;
            alu_opa_zero         <= '1';

        elsif  std_match(IR, NEGC_RM_RN) then  -- NEGC Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= ("0000" & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_NEGC;
            alu_sh2              <= "00000001100";
            alu_opa_zero         <= '1';

        elsif  std_match(IR, DT_RN) then  -- DT Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGIMM;
            alu_gen              <= "11110000001";
            alu_sh2              <= "00000000011";
            tbit_write           <= '1';

        elsif  std_match(IR, AND_RM_RN) then  -- AND Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_AND;

        elsif  std_match(IR, AND_IMM_IMM_R0) then  -- AND #imm,R0
            reg_ALU_IN           <= REG_IN_R0_REGFILE;
            alu_IN               <= ALU_IN_REGIMM;
            alu_gen              <= ALU_GEN_AND;

        elsif  std_match(IR, AND_B_IMM_IMM_AT_R0_GBR) then  -- AND.B #imm,@(R0,GBR)
            alu_IN               <= ALU_IN_DATAIMM;
            alu_gen              <= ALU_GEN_AND;
            alu_opa_hold         <= '1';
            dau_controls         <= "0100010000";
            RE                   <= RE_BYTE;
            WE                   <= WE_BYTE;
            is_mem               <= '1';
            is_rmw               <= '1';

        elsif  std_match(IR, OR_RM_RN) then  -- OR Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_OR;

        elsif  std_match(IR, OR_IMM_IMM_R0) then  -- OR #imm,R0
            reg_ALU_IN           <= REG_IN_R0_REGFILE;
            alu_IN               <= ALU_IN_REGIMM;
            alu_gen              <= ALU_GEN_OR;

        elsif  std_match(IR, OR_B_IMM_IMM_AT_R0_GBR) then  -- OR.B #imm,@(R0,GBR)
            alu_IN               <= ALU_IN_DATAIMM;
            alu_gen              <= ALU_GEN_OR;
            alu_opa_hold         <= '1';
            dau_controls         <= "0100010000";
            RE                   <= RE_BYTE;
            WE                   <= WE_BYTE;
            is_mem               <= '1';
            is_rmw               <= '1';

        elsif  std_match(IR, XOR_RM_RN) then  -- XOR Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_XOR;

        elsif  std_match(IR, XOR_IMM_IMM_R0) then  -- XOR #imm,R0
            reg_ALU_IN           <= REG_IN_R0_REGFILE;
            alu_IN               <= ALU_IN_REGIMM;
            alu_gen              <= ALU_GEN_XOR;

        elsif  std_match(IR, XOR_B_IMM_IMM_AT_R0_GBR) then  -- XOR.B #imm,@(R0,GBR)
            alu_IN               <= ALU_IN_DATAIMM;
            alu_gen              <= ALU_GEN_XOR;
            alu_opa_hold         <= '1';
            dau_controls         <= "0100010000";
            RE                   <= RE_BYTE;
            WE                   <= WE_BYTE;
            is_mem               <= '1';
            is_rmw               <= '1';

        elsif  std_match(IR, NOT_RM_RN) then  -- NOT Rm,Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (mreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_NOT;

        elsif  std_match(IR, TST_RM_RN) then  -- TST Rm,Rn
            reg_MAU              <= (nreg & mreg & "000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_AND;
            alu_sh2              <= "00000000011";
            tbit_write           <= '1';

        elsif  std_match(IR, TST_IMM_IMM_R0) then  -- TST #imm,R0
            alu_IN               <= ALU_IN_REGIMM;
            alu_gen              <= ALU_GEN_AND;
            alu_sh2              <= "00000000011";
            tbit_write           <= '1';

        elsif  std_match(IR, TST_B_IMM_IMM_AT_R0_GBR) then  -- TST.B #imm,@(R0,GBR)
            alu_IN               <= ALU_IN_DATAIMM;
            alu_gen              <= ALU_GEN_AND;
            alu_opa_hold         <= '1';
            alu_sh2              <= "00000000011";
            dau_controls         <= "0100010000";
            RE                   <= RE_BYTE;
            tbit_write           <= '1';
            is_mem               <= '1';
            is_rmw               <= '1';

        elsif  std_match(IR, TAS_B_AT_RN) then  -- TAS.B @Rn
            reg_MAU              <= ("0000000000000" & nreg);
            alu_IN               <= "0-";
            alu_gen              <= ALU_GEN_OR;
            alu_opa_hold         <= '1';
            alu_opb_bit7         <= '1';
            alu_sh2              <= "00000001111";
            RE                   <= RE_BYTE;
            WE                   <= WE_BYTE;
            tbit_write           <= '1';
            is_mem               <= '1';
            is_rmw               <= '1';

        elsif  std_match(IR, ROTL_RN) then  -- ROTL Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_ROTL;
            alu_sh2              <= "00000000001";
            tbit_write           <= '1';

        elsif  std_match(IR, ROTR_RN) then  -- ROTR Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_ROTR;
            alu_sh2              <= "00000000001";
            tbit_write           <= '1';

        elsif  std_match(IR, ROTCL_RN) then  -- ROTCL Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_ROTCL;
            alu_sh2              <= "00000000001";
            tbit_write           <= '1';

        elsif  std_match(IR, ROTCR_RN) then  -- ROTCR Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_ROTCR;
            alu_sh2              <= "00000000001";
            tbit_write           <= '1';

        elsif  std_match(IR, SHLL_RN) then  -- SHLL Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SHLL1;
            alu_sh2              <= "00000000001";
            tbit_write           <= '1';

        elsif  std_match(IR, SHLR_RN) then  -- SHLR Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SHLR1_L;
            alu_sh2              <= "00000000001";
            tbit_write           <= '1';

        elsif  std_match(IR, SHAL_RN) then  -- SHAL Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SHLL1;
            alu_sh2              <= "00000000001";
            tbit_write           <= '1';

        elsif  std_match(IR, SHAR_RN) then  -- SHAR Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SHLR1_A;
            alu_sh2              <= "00000000001";
            tbit_write           <= '1';

        elsif  std_match(IR, SHLL2_RN) then  -- SHLL2 Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            alu_sh2              <= "00000010000";

        elsif  std_match(IR, SHLL8_RN) then  -- SHLL8 Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            alu_sh2              <= "01000010000";

        elsif  std_match(IR, SHLL16_RN) then  -- SHLL16 Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            alu_sh2              <= "10000010000";

        elsif  std_match(IR, SHLR2_RN) then  -- SHLR2 Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SHLR_N;
            alu_sh2              <= "00000010000";

        elsif  std_match(IR, SHLR8_RN) then  -- SHLR8 Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SHLR_N;
            alu_sh2              <= "01000010000";

        elsif  std_match(IR, SHLR16_RN) then  -- SHLR16 Rn
            reg_ALU_IN           <= ("000" & nreg & "1");
            reg_MAU              <= (nreg & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_SHLR_N;
            alu_sh2              <= "10000010000";

        -- Branch instructions: always compute target, decision in EX
        elsif  std_match(IR, BT_LABEL) then  -- BT label
            pau_controls         <= PAU_BRANCH_DISP;
            is_branch            <= '1';
            is_cond_branch       <= '1';
            is_BT                <= '1';

        elsif  std_match(IR, BF_LABEL) then  -- BF label
            pau_controls         <= PAU_BRANCH_DISP;
            is_branch            <= '1';
            is_cond_branch       <= '1';
            is_BF                <= '1';

        elsif  std_match(IR, BT_S_LABEL) then  -- BT/S label (delayed conditional)
            pau_controls         <= PAU_BRANCH_DISP;
            delay_slot           <= '1';
            is_branch            <= '1';
            is_cond_branch       <= '1';
            is_BT                <= '1';

        elsif  std_match(IR, BF_S_LABEL) then  -- BF/S label (delayed conditional)
            pau_controls         <= PAU_BRANCH_DISP;
            delay_slot           <= '1';
            is_branch            <= '1';
            is_cond_branch       <= '1';
            is_BF                <= '1';

        elsif  std_match(IR, BRA_LABEL) then  -- BRA label (delayed)
            imm_sel              <= "10";
            pau_controls         <= PAU_BRANCH_DISP;
            delay_slot           <= '1';
            is_branch            <= '1';

        elsif  std_match(IR, BRAF_RM) then  -- BRAF Rm (delayed)
            reg_MAU              <= (IR(11 downto 8) & "0000000000000");
            pau_controls         <= PAU_BRANCH_REG;
            delay_slot           <= '1';
            is_branch            <= '1';

        elsif  std_match(IR, BSR_LABEL) then  -- BSR label (delayed)
            imm_sel              <= "10";
            pau_controls         <= PAU_BSR;
            delay_slot           <= '1';
            is_branch            <= '1';

        elsif  std_match(IR, BSRF_RM) then  -- BSRF Rm (delayed)
            reg_MAU              <= (IR(11 downto 8) & "0000000000000");
            pau_controls         <= PAU_BSRF;
            delay_slot           <= '1';
            is_branch            <= '1';

        elsif  std_match(IR, JMP_AT_RM) then  -- JMP @Rm (delayed)
            reg_MAU              <= (IR(11 downto 8) & "0000000000000");
            pau_controls         <= PAU_JMP;
            delay_slot           <= '1';
            is_branch            <= '1';

        elsif  std_match(IR, JSR_AT_RM) then  -- JSR @Rm (delayed)
            reg_MAU              <= (IR(11 downto 8) & "0000000000000");
            pau_controls         <= PAU_JSR;
            delay_slot           <= '1';
            is_branch            <= '1';

        elsif  std_match(IR, RTS) then  -- RTS (delayed)
            pau_controls         <= PAU_RTS;
            delay_slot           <= '1';
            is_branch            <= '1';

        elsif  std_match(IR, CLRT) then  -- CLRT
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_NONE;
            alu_sh2              <= "00000001101";
            tbit_write           <= '1';

        elsif  std_match(IR, SETT) then  -- SETT
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_NONE;
            alu_sh2              <= "00000001110";
            tbit_write           <= '1';

        elsif  std_match(IR, NOP) then  -- NOP
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;

        elsif  std_match(IR, LDC_RM_GBR) then  -- LDC Rm,GBR
            reg_MAU              <= (IR(11 downto 8) & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_write            <= DAU_WRITE_GBR;

        elsif  std_match(IR, LDC_RM_VBR) then  -- LDC Rm,VBR
            reg_MAU              <= (IR(11 downto 8) & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_write            <= DAU_WRITE_VBR;

        elsif  std_match(IR, LDC_L_AT_RM_PLUS_GBR) then  -- LDC.L @Rm+,GBR
            reg_MAU              <= ("00000000" & IR(11 downto 8) & "1" & IR(11 downto 8));
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000100100";
            dau_write            <= DAU_WRITE_GBR;
            dau_load_data        <= '1';
            RE                   <= RE_LONG;
            is_mem               <= '1';

        elsif  std_match(IR, LDC_L_AT_RM_PLUS_VBR) then  -- LDC.L @Rm+,VBR
            reg_MAU              <= ("00000000" & IR(11 downto 8) & "1" & IR(11 downto 8));
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000100100";
            dau_write            <= DAU_WRITE_VBR;
            dau_load_data        <= '1';
            RE                   <= RE_LONG;
            is_mem               <= '1';

        elsif  std_match(IR, LDC_L_AT_RM_PLUS_SR) then  -- LDC.L @Rm+,SR
            reg_MAU              <= ("00000000" & IR(11 downto 8) & "1" & IR(11 downto 8));
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000100100";
            alu_sh2              <= "00000001010";
            tbit_write           <= '1';
            RE                   <= RE_LONG;
            is_mem               <= '1';
            is_load              <= '1';

        elsif  std_match(IR, STC_SR_RN) then  -- STC SR,Rn
            reg_ALU_IN           <= ("101" & nreg & "1");

        elsif  std_match(IR, STC_GBR_RN) then  -- STC GBR,Rn
            reg_ALU_IN           <= ("100" & nreg & "1");
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0100100000";
            dau_out_sel          <= "01";

        elsif  std_match(IR, STC_VBR_RN) then  -- STC VBR,Rn
            reg_ALU_IN           <= ("100" & nreg & "1");
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "1000100000";
            dau_out_sel          <= "10";

        elsif  std_match(IR, STC_L_SR_AT_MINUSRN) then  -- STC.L SR,@-Rn
            reg_MAU              <= ("00000000" & nreg & "1" & nreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000101101";
            data_bus_sel         <= "10";
            WE                   <= WE_LONG;
            is_mem               <= '1';

        elsif  std_match(IR, STC_L_GBR_AT_MINUSRN) then  -- STC.L GBR,@-Rn
            reg_MAU              <= ("00000000" & nreg & "1" & nreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000101101";
            dau_out_sel          <= "01";
            data_bus_sel         <= "01";
            WE                   <= WE_LONG;
            is_mem               <= '1';

        elsif  std_match(IR, STC_L_VBR_AT_MINUSRN) then  -- STC.L VBR,@-Rn
            reg_MAU              <= ("00000000" & nreg & "1" & nreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000101101";
            dau_out_sel          <= "10";
            data_bus_sel         <= "01";
            WE                   <= WE_LONG;
            is_mem               <= '1';

        elsif  std_match(IR, LDS_RM_PR) then  -- LDS Rm,PR
            reg_MAU              <= (IR(11 downto 8) & "0000000000000");
            alu_IN               <= ALU_IN_REGREG;
            alu_gen              <= ALU_GEN_PASS;
            pau_controls         <= "001010";  -- pr_sel = "10" (write PR from register/ALU)

        elsif  std_match(IR, LDS_L_AT_RM_PLUS_PR) then  -- LDS.L @Rm+,PR
            reg_MAU              <= ("00000000" & IR(11 downto 8) & "1" & IR(11 downto 8));
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000100100";
            pau_controls         <= PAU_LDS_PR;  -- pr_sel = "11" (write PR from memory)
            RE                   <= RE_LONG;
            is_mem               <= '1';

        elsif  std_match(IR, STS_PR_RN) then  -- STS PR,Rn
            reg_ALU_IN           <= ("011" & nreg & "1");
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;

        elsif  std_match(IR, STS_L_PR_AT_MINUSRN) then  -- STS.L PR,@-Rn
            reg_MAU              <= ("00000000" & nreg & "1" & nreg);
            alu_IN               <= ALU_IN_DATAREG;
            alu_gen              <= ALU_GEN_PASS;
            dau_controls         <= "0000101101";
            data_bus_sel         <= "11";
            WE                   <= WE_LONG;
            is_mem               <= '1';

        end if;

    end process;

end structural;
