----------------------------------------------------------------------------
--
--  SH-2 Control Unit
--
--  This is a package wih all the instruction constants for the SH-2. These are 
--  used in the control unit to generate the appropriate control signals for each instruction. 
--  They are defined as constants with the appropriate bits set and don't-cares 
--  where the instruction fields vary. MAC, MUL, DIV, and other instructions that
--  are not implementing are not included.
--
--  Packages included are:
--     InstructionConstants  - the instruction constants
--
--  Revision History:
--     26 Apr 26  Simone Shevchuk       Initial revision.
--     28 Apr 26  Simone Shevchuk       Add constants for common load values
--     30 Apr 26  Simone Shevchuk       Add type records to unpack in CPU
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package  InstructionConstants  is

    -- =========================================================
    -- Opcode pattern constants  (don't-cares where reg or imm)
    -- =========================================================

    constant RESET_VECTOR_AT_0                : std_logic_vector(15 downto 0) := "0000000000000000"; 
    constant MOV_IMM_IMM_RN                   : std_logic_vector(15 downto 0) := "1110------------";
    constant MOV_RM_RN                        : std_logic_vector(15 downto 0) := "0110--------0011";
    constant MOV_W_AT_DISP_PC_RN              : std_logic_vector(15 downto 0) := "1001------------";
    constant MOV_L_AT_DISP_PC_RN              : std_logic_vector(15 downto 0) := "1101------------";
    constant MOV_B_RM_AT_RN                   : std_logic_vector(15 downto 0) := "0010--------0000";
    constant MOV_W_RM_AT_RN                   : std_logic_vector(15 downto 0) := "0010--------0001";
    constant MOV_L_RM_AT_RN                   : std_logic_vector(15 downto 0) := "0010--------0010";
    constant MOV_B_AT_RM_RN                   : std_logic_vector(15 downto 0) := "0110--------0000";
    constant MOV_W_AT_RM_RN                   : std_logic_vector(15 downto 0) := "0110--------0001";
    constant MOV_L_AT_RM_RN                   : std_logic_vector(15 downto 0) := "0110--------0010";
    constant MOV_B_AT_RM_PLUS_RN              : std_logic_vector(15 downto 0) := "0110--------0100";
    constant MOV_W_AT_RM_PLUS_RN              : std_logic_vector(15 downto 0) := "0110--------0101";
    constant MOV_L_AT_RM_PLUS_RN              : std_logic_vector(15 downto 0) := "0110--------0110";
    constant MOV_B_RM_AT_MINUSRN              : std_logic_vector(15 downto 0) := "0010--------0100";
    constant MOV_W_RM_AT_MINUSRN              : std_logic_vector(15 downto 0) := "0010--------0101";
    constant MOV_L_RM_AT_MINUSRN              : std_logic_vector(15 downto 0) := "0010--------0110";
    constant MOV_B_R0_AT_DISP_RN              : std_logic_vector(15 downto 0) := "10000000--------";
    constant MOV_W_R0_AT_DISP_RN              : std_logic_vector(15 downto 0) := "10000001--------";
    constant MOV_L_RM_AT_DISP_RN              : std_logic_vector(15 downto 0) := "0001------------";
    constant MOV_B_AT_DISP_RM_R0              : std_logic_vector(15 downto 0) := "10000100--------";
    constant MOV_W_AT_DISP_RM_R0              : std_logic_vector(15 downto 0) := "10000101--------";
    constant MOV_L_AT_DISP_RM_RN              : std_logic_vector(15 downto 0) := "0101------------";
    constant MOV_B_RM_AT_R0_RN                : std_logic_vector(15 downto 0) := "0000--------0100";
    constant MOV_W_RM_AT_R0_RN                : std_logic_vector(15 downto 0) := "0000--------0101";
    constant MOV_L_RM_AT_R0_RN                : std_logic_vector(15 downto 0) := "0000--------0110";
    constant MOV_B_AT_R0_RM_RN                : std_logic_vector(15 downto 0) := "0000--------1100";
    constant MOV_W_AT_R0_RM_RN                : std_logic_vector(15 downto 0) := "0000--------1101";
    constant MOV_L_AT_R0_RM_RN                : std_logic_vector(15 downto 0) := "0000--------1110";
    constant MOV_B_R0_AT_DISP_GBR             : std_logic_vector(15 downto 0) := "11000000--------";
    constant MOV_W_R0_AT_DISP_GBR             : std_logic_vector(15 downto 0) := "11000001--------";
    constant MOV_L_R0_AT_DISP_GBR             : std_logic_vector(15 downto 0) := "11000010--------";
    constant MOV_B_AT_DISP_GBR_R0             : std_logic_vector(15 downto 0) := "11000100--------";
    constant MOV_W_AT_DISP_GBR_R0             : std_logic_vector(15 downto 0) := "11000101--------";
    constant MOV_L_AT_DISP_GBR_R0             : std_logic_vector(15 downto 0) := "11000110--------";
    constant MOVA_AT_DISP_PC_R0               : std_logic_vector(15 downto 0) := "11000111--------";
    constant MOVT_RN                          : std_logic_vector(15 downto 0) := "0000----00101001";
    constant SWAP_B_RM_RN                     : std_logic_vector(15 downto 0) := "0110--------1000";
    constant SWAP_W_RM_RN                     : std_logic_vector(15 downto 0) := "0110--------1001";
    constant XTRCT_RM_RN                      : std_logic_vector(15 downto 0) := "0010--------1101";
    constant ADD_RM_RN                        : std_logic_vector(15 downto 0) := "0011--------1100";
    constant ADD_IMM_IMM_RN                   : std_logic_vector(15 downto 0) := "0111------------";
    constant ADDC_RM_RN                       : std_logic_vector(15 downto 0) := "0011--------1110";
    constant ADDV_RM_RN                       : std_logic_vector(15 downto 0) := "0011--------1111";
    constant CMP_EQ_RM_RN                     : std_logic_vector(15 downto 0) := "0011--------0000";
    constant CMP_EQ_IMM_IMM_R0                : std_logic_vector(15 downto 0) := "10001000--------";
    constant CMP_GE_RM_RN                     : std_logic_vector(15 downto 0) := "0011--------0011";
    constant CMP_GT_RM_RN                     : std_logic_vector(15 downto 0) := "0011--------0111";
    constant CMP_HI_RM_RN                     : std_logic_vector(15 downto 0) := "0011--------0110";
    constant CMP_HS_RM_RN                     : std_logic_vector(15 downto 0) := "0011--------0010";
    constant CMP_PL_RN                        : std_logic_vector(15 downto 0) := "0100----00010101";
    constant CMP_PZ_RN                        : std_logic_vector(15 downto 0) := "0100----00010001";
    constant CMP_STR_RM_RN                    : std_logic_vector(15 downto 0) := "0010--------1100";
    constant EXTS_B_RM_RN                     : std_logic_vector(15 downto 0) := "0110--------1110";
    constant EXTS_W_RM_RN                     : std_logic_vector(15 downto 0) := "0110--------1111";
    constant EXTU_B_RM_RN                     : std_logic_vector(15 downto 0) := "0110--------1100";
    constant EXTU_W_RM_RN                     : std_logic_vector(15 downto 0) := "0110--------1101";
    constant SUB_RM_RN                        : std_logic_vector(15 downto 0) := "0011--------1000";
    constant SUBC_RM_RN                       : std_logic_vector(15 downto 0) := "0011--------1010";
    constant SUBV_RM_RN                       : std_logic_vector(15 downto 0) := "0011--------1011";
    constant NEG_RM_RN                        : std_logic_vector(15 downto 0) := "0110--------1011";
    constant NEGC_RM_RN                       : std_logic_vector(15 downto 0) := "0110--------1010";
    constant DT_RN                            : std_logic_vector(15 downto 0) := "0100----00010000";
    constant AND_RM_RN                        : std_logic_vector(15 downto 0) := "0010--------1001";
    constant AND_IMM_IMM_R0                   : std_logic_vector(15 downto 0) := "11001001--------";
    constant AND_B_IMM_IMM_AT_R0_GBR          : std_logic_vector(15 downto 0) := "11001101--------";
    constant OR_RM_RN                         : std_logic_vector(15 downto 0) := "0010--------1011";
    constant OR_IMM_IMM_R0                    : std_logic_vector(15 downto 0) := "11001011--------";
    constant OR_B_IMM_IMM_AT_R0_GBR           : std_logic_vector(15 downto 0) := "11001111--------";
    constant XOR_RM_RN                        : std_logic_vector(15 downto 0) := "0010--------1010";
    constant XOR_IMM_IMM_R0                   : std_logic_vector(15 downto 0) := "11001010--------";
    constant XOR_B_IMM_IMM_AT_R0_GBR          : std_logic_vector(15 downto 0) := "11001110--------";
    constant NOT_RM_RN                        : std_logic_vector(15 downto 0) := "0110--------0111";
    constant TST_RM_RN                        : std_logic_vector(15 downto 0) := "0010--------1000";
    constant TST_IMM_IMM_R0                   : std_logic_vector(15 downto 0) := "11001000--------";
    constant TST_B_IMM_IMM_AT_R0_GBR          : std_logic_vector(15 downto 0) := "11001100--------";
    constant TAS_B_AT_RN                      : std_logic_vector(15 downto 0) := "0100----00011011";
    constant ROTL_RN                          : std_logic_vector(15 downto 0) := "0100----00000100";
    constant ROTR_RN                          : std_logic_vector(15 downto 0) := "0100----00000101";
    constant ROTCL_RN                         : std_logic_vector(15 downto 0) := "0100----00100100";
    constant ROTCR_RN                         : std_logic_vector(15 downto 0) := "0100----00100101";
    constant SHLL_RN                          : std_logic_vector(15 downto 0) := "0100----00000000";
    constant SHLR_RN                          : std_logic_vector(15 downto 0) := "0100----00000001";
    constant SHAL_RN                          : std_logic_vector(15 downto 0) := "0100----00100000";
    constant SHAR_RN                          : std_logic_vector(15 downto 0) := "0100----00100001";
    constant SHLL2_RN                         : std_logic_vector(15 downto 0) := "0100----00001000";
    constant SHLL8_RN                         : std_logic_vector(15 downto 0) := "0100----00011000";
    constant SHLL16_RN                        : std_logic_vector(15 downto 0) := "0100----00101000";
    constant SHLR2_RN                         : std_logic_vector(15 downto 0) := "0100----00001001";
    constant SHLR8_RN                         : std_logic_vector(15 downto 0) := "0100----00011001";
    constant SHLR16_RN                        : std_logic_vector(15 downto 0) := "0100----00101001";
    constant BT_LABEL                         : std_logic_vector(15 downto 0) := "10001001--------";
    constant BF_LABEL                         : std_logic_vector(15 downto 0) := "10001011--------";
    constant BT_S_LABEL                       : std_logic_vector(15 downto 0) := "10001101--------";
    constant BF_S_LABEL                       : std_logic_vector(15 downto 0) := "10001111--------";
    constant BRA_LABEL                        : std_logic_vector(15 downto 0) := "1010------------";
    constant BRAF_RM                          : std_logic_vector(15 downto 0) := "0000----00100011";
    constant BSR_LABEL                        : std_logic_vector(15 downto 0) := "1011------------";
    constant BSRF_RM                          : std_logic_vector(15 downto 0) := "0000----00000011";
    constant JMP_AT_RM                        : std_logic_vector(15 downto 0) := "0100----00101011";
    constant JSR_AT_RM                        : std_logic_vector(15 downto 0) := "0100----00001011";
    constant RTS                              : std_logic_vector(15 downto 0) := "0000000000001011";
    constant CLRT                             : std_logic_vector(15 downto 0) := "0000000000001000";
    constant SETT                             : std_logic_vector(15 downto 0) := "0000000000011000";
    constant NOP                              : std_logic_vector(15 downto 0) := "0000000000001001";
    constant LDC_RM_GBR                       : std_logic_vector(15 downto 0) := "0100----00011110";
    constant LDC_RM_VBR                       : std_logic_vector(15 downto 0) := "0100----00101110";
    constant LDC_L_AT_RM_PLUS_GBR             : std_logic_vector(15 downto 0) := "0100----00010111";
    constant LDC_L_AT_RM_PLUS_VBR             : std_logic_vector(15 downto 0) := "0100----00100111";
    constant LDC_L_AT_RM_PLUS_SR              : std_logic_vector(15 downto 0) := "0100----00000111";
    constant STC_SR_RN                        : std_logic_vector(15 downto 0) := "0000----00000010";
    constant STC_GBR_RN                       : std_logic_vector(15 downto 0) := "0000----00010010";
    constant STC_VBR_RN                       : std_logic_vector(15 downto 0) := "0000----00100010";
    constant STC_L_SR_AT_MINUSRN              : std_logic_vector(15 downto 0) := "0100----00000011";
    constant STC_L_GBR_AT_MINUSRN             : std_logic_vector(15 downto 0) := "0100----00010011";
    constant STC_L_VBR_AT_MINUSRN             : std_logic_vector(15 downto 0) := "0100----00100011";
    constant LDS_RM_PR                        : std_logic_vector(15 downto 0) := "0100----00101010";
    constant LDS_L_AT_RM_PLUS_PR              : std_logic_vector(15 downto 0) := "0100----00100110";
    constant STS_PR_RN                        : std_logic_vector(15 downto 0) := "0000----00101010";
    constant STS_L_PR_AT_MINUSRN              : std_logic_vector(15 downto 0) := "0100----00100010";

    -- ============================================================
    -- ControlSH2 common control signal constants
    -- ============================================================

    -- reg_ALU_IN  [2(reg_in_src) | 4(reg_in_sel) | 1(reg_store)]
    constant REG_IN_NONE        : std_logic_vector(7 downto 0) := "00000000"; -- no reg write
    constant REG_IN_R0_ONLY     : std_logic_vector(7 downto 0) := "00100001"; -- write R0 src=datadatabus
    constant REG_IN_R0_REGFILE  : std_logic_vector(7 downto 0) := "00000001"; -- write R0, src=regfile through ALU? or ALU

    -- reg_MAU  [4(reg_a_sel) | 4(reg_b_sel) | 4(reg_ax_sel) | 1(reg_ax_store) | 4(reg_a2_sel)]
    constant REG_MAU_NONE           : std_logic_vector(16 downto 0) := "00000000000000000";

    -- alu_in [1(alu_sel_a) + 1(alu_sel_b)]
    constant ALU_IN_DATAREG             : std_logic_vector(1 downto 0) := "00"; -- A=datadatabus B=reg
    constant ALU_IN_DATAIMM            : std_logic_vector(1 downto 0) := "01"; -- A=datadatabus B=immediate
    constant ALU_IN_REGREG           : std_logic_vector(1 downto 0) := "10"; -- A=reg B=reg
    constant ALU_IN_REGIMM           : std_logic_vector(1 downto 0) := "11"; -- A=reg, B=immediate

    -- alu_gen  [4(f_cmd) | 2(c_in_cmd) | 3(s_cmd) | 2(alu_cmd)]
    constant ALU_GEN_PASS       : std_logic_vector(10 downto 0) := "11000000000"; -- pass / NOP
    constant ALU_GEN_IMM        : std_logic_vector(10 downto 0) := "10100000000"; -- load immediate
    constant ALU_GEN_ADD        : std_logic_vector(10 downto 0) := "10100000001"; -- ADD
    constant ALU_GEN_ADDC       : std_logic_vector(10 downto 0) := "10101000001"; -- ADDC
    constant ALU_GEN_SUB        : std_logic_vector(10 downto 0) := "01010100001"; -- SUB / CMP
    constant ALU_GEN_SUBC       : std_logic_vector(10 downto 0) := "01011100001"; -- SUBC
    constant ALU_GEN_AND        : std_logic_vector(10 downto 0) := "10000000000"; -- AND
    constant ALU_GEN_OR         : std_logic_vector(10 downto 0) := "11100000000"; -- OR
    constant ALU_GEN_XOR        : std_logic_vector(10 downto 0) := "01100000000"; -- XOR
    constant ALU_GEN_NOT        : std_logic_vector(10 downto 0) := "00110000000"; -- NOT
    constant ALU_GEN_NEG        : std_logic_vector(10 downto 0) := "01010100001"; -- NEG (NOT B, cin=1, adder)
    constant ALU_GEN_NEGC       : std_logic_vector(10 downto 0) := "01011100001"; -- NEGC (NOT B, cin=~C, adder)
    constant ALU_GEN_SUBV       : std_logic_vector(10 downto 0) := "01010100001"; -- SUBV
    constant ALU_GEN_CMP_STR    : std_logic_vector(10 downto 0) := "01100000000"; -- CMP/STR (XOR)
    constant ALU_GEN_SHLL1      : std_logic_vector(10 downto 0) := "11000000010"; -- shift left 1  (SHLL/SHAL)
    constant ALU_GEN_SHLR1_L    : std_logic_vector(10 downto 0) := "11000010010"; -- shift right 1 logical (SHLR)
    constant ALU_GEN_SHLR1_A    : std_logic_vector(10 downto 0) := "11000010110"; -- shift right 1 arith (SHAR)
    constant ALU_GEN_SHLR_N     : std_logic_vector(10 downto 0) := "11000010000"; -- SHLRn (2/8/16)
    constant ALU_GEN_ROTL       : std_logic_vector(10 downto 0) := "11000001010"; -- ROTL
    constant ALU_GEN_ROTR       : std_logic_vector(10 downto 0) := "11000011010"; -- ROTR
    constant ALU_GEN_ROTCL      : std_logic_vector(10 downto 0) := "11001001110"; -- ROTCL
    constant ALU_GEN_ROTCR      : std_logic_vector(10 downto 0) := "11001011110"; -- ROTCR
    constant ALU_GEN_NONE       : std_logic_vector(10 downto 0) := "00000000000"; -- no ALU op

    -- alu_sh2 [2(shift_sel) + 2(extend_sel) + 3(res_sel) + 4(t_sel)]
    constant ALU_SH2_NONE       : std_logic_vector(10 downto 0) := "00000000000"; -- no fancy sh2 select generic

    -- pau_controls  [2(pau_src_sel) | 2(pau_offset_sel) | 2(pr_sel)]
    constant PAU_HOLD           : std_logic_vector(5 downto 0) := "000000"; -- hold (no fetch)
    constant PAU_SEQ            : std_logic_vector(5 downto 0) := "001100"; -- sequential fetch (PC+2)
    constant PAU_BRANCH_DISP    : std_logic_vector(5 downto 0) := "110000"; -- PC+4 relative branch
    constant PAU_BRANCH_REG     : std_logic_vector(5 downto 0) := "110100"; -- BRAF Rm (PC+4 + Rm)
    constant PAU_BSR            : std_logic_vector(5 downto 0) := "110001"; -- BSR (PC+4 base, save PR)
    constant PAU_BSRF           : std_logic_vector(5 downto 0) := "110101"; -- BSRF Rm (PC+4 + Rm, save PR)
    constant PAU_JMP            : std_logic_vector(5 downto 0) := "101000"; -- JMP @Rm
    constant PAU_JSR            : std_logic_vector(5 downto 0) := "101001"; -- JSR @Rm (save PR)
    constant PAU_RTS            : std_logic_vector(5 downto 0) := "011000"; -- RTS (restore PR)
    constant PAU_LDS_PR         : std_logic_vector(5 downto 0) := "001011"; -- LDS.L @Rm+,PR (pr_sel=3: load PR from data bus)

    -- dau_controls [2(dau_src_sel) + 2(dau_shift_sel) + 2(dau_offset_sel) + 1(dau_inc_dec_sel) + 2(dau_inc_dec_bit) + 1(dau_pre_post_sel)]
    constant DAU_CTRL_NONE           : std_logic_vector(9 downto 0) := "0000100000"; -- no DAU operation / pass through source
    constant DAU_CTRL_OFFSET_DISP8   : std_logic_vector(9 downto 0) := "0000000000"; -- use 8-bit displacement as offset

    -- dau_write  [1(gbr_write) | 1(vbr_write)]
    constant DAU_WRITE_NONE     : std_logic_vector(1 downto 0) := "00";
    constant DAU_WRITE_GBR      : std_logic_vector(1 downto 0) := "10";
    constant DAU_WRITE_VBR      : std_logic_vector(1 downto 0) := "01";

    -- RE / WE byte-enable patterns  (active-low: '0' = enabled)
    constant RE_NONE            : std_logic_vector(3 downto 0) := "1111"; -- no read
    constant RE_BYTE            : std_logic_vector(3 downto 0) := "1110"; -- byte read
    constant RE_WORD            : std_logic_vector(3 downto 0) := "1100"; -- word read
    constant RE_LONG            : std_logic_vector(3 downto 0) := "0000"; -- longword read
    constant WE_NONE            : std_logic_vector(3 downto 0) := "1111"; -- no write
    constant WE_BYTE            : std_logic_vector(3 downto 0) := "1110"; -- byte write
    constant WE_WORD            : std_logic_vector(3 downto 0) := "1100"; -- word write
    constant WE_LONG            : std_logic_vector(3 downto 0) := "0000"; -- longword write

    -- ============================================================
    -- Index constants for instruction fields (for unpacking in CPU)
    -- ============================================================
    -- for reg_ALU_IN  [3(reg_in_src) + 4(reg_in_sel) + 1(reg_store)]  MSB-first
    constant REG_IN_SRC_IDX       : integer := 7;
    constant REG_IN_SEL_IDX       : integer := 4;
    constant REG_STORE_IDX        : integer := 0;

    -- for reg_MAU  [4(reg_a_sel) + 4(reg_b_sel) + 4(reg_ax_sel) + 1(reg_ax_store) + 4(reg_a2_sel)]  MSB-first
    constant REG_MAU_A_SEL_IDX        : integer := 16;
    constant REG_MAU_B_SEL_IDX        : integer := 12;
    constant REG_MAU_AX_SEL_IDX       : integer := 8;
    constant REG_MAU_AX_STORE_IDX     : integer := 4;
    constant REG_MAU_A2_SEL_IDX       : integer := 3;

    -- for alu_in  [1(alu_sel_a) + 1(alu_sel_b)]  MSB-first
    constant ALU_SEL_A_IDX       : integer := 1;
    constant ALU_SEL_B_IDX       : integer := 0;

    -- for alu_gen  [4(f_cmd) + 2(c_in_cmd) + 3(s_cmd) + 2(alu_cmd)]  MSB-first
    constant ALU_F_CMD_IDX       : integer := 10;
    constant ALU_C_IN_CMD_IDX    : integer := 6;
    constant ALU_S_CMD_IDX       : integer := 4;
    constant ALU_ALU_CMD_IDX     : integer := 1;

    -- for alu_sh2  [2(shift_sel) + 2(extend_sel) + 3(res_sel) + 4(t_sel)]  MSB-first
    constant ALU_SHIFT_SEL_IDX   : integer := 10;
    constant ALU_EXTEND_SEL_IDX  : integer := 8;
    constant ALU_RES_SEL_IDX     : integer := 6;
    constant ALU_T_SEL_IDX       : integer := 3;

    -- for dau_controls  [2(dau_src_sel) + 2(dau_shift_sel) + 2(dau_offset_sel) + 1(dau_inc_dec_sel) + 2(dau_inc_dec_bit) + 1(dau_pre_post_sel)]  MSB-first
    constant DAU_SRC_SEL_IDX         : integer := 9;
    constant DAU_SHIFT_SEL_IDX       : integer := 7;
    constant DAU_OFFSET_SEL_IDX      : integer := 5;
    constant DAU_INC_DEC_SEL_IDX     : integer := 3;
    constant DAU_INC_DEC_BIT_IDX     : integer := 2;
    constant DAU_PRE_POST_SEL_IDX    : integer := 0;

    -- for dau_write  [1(gbr_write) + 1(vbr_write)]  MSB-first
    constant DAU_WRITE_GBR_IDX       : integer := 1;
    constant DAU_WRITE_VBR_IDX       : integer := 0;

    -- for pau_controls  [2(pau_src_sel) + 2(pau_offset_sel) + 2(pr_sel)]  MSB-first
    constant PAU_SRC_SEL_IDX         : integer := 5;
    constant PAU_OFFSET_SEL_IDX      : integer := 3;
    constant PAU_PR_SEL_IDX          : integer := 1;

end  InstructionConstants;
