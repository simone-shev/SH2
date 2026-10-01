----------------------------------------------------------------------------
--
--  Hitachi SH-2 CPU Entity Declaration (Pipelined)
--
--  This is the entity declaration for the complete SH-2 CPU.  The design
--  should implement this entity to make testing possible.
--
--  Revision History:
--     28 Apr 25  Glen George       Initial revision.
--     29 Apr 26  Simone Shevchuk   Initial revision.
--     01 May 26  Simone Shevchuk   Tri state busses and read/write, add addr_bit(1) as control input for IR
--     05 May 26  Simone Shevchuk   Add imm_sel control signal for selecting type of immediate value and add control signals for NEG/NEGC
--     10 May 26  Simone Shevchuk   Sign extend databus for byte and word access
--     08 May 26  Simone Shevchuk    Update ALU inputs
--     11 May 26  Simone Shevchuk   Register the db value
--     12 May 26  Simone Shevchuk   Zero-extend s_db_hold for byte RMW ALU ops,
--                                  add alu_opb_bit7 mux for TAS.B bit 7 set.
--                                  Update input for PAU to be from reg_a for jump
--     16 May 26  Simone Shevchuk   Pipeline 5-stage IF/ID/EX/MEM/WB with pipeline
--                                  registers
--     18 May 26  Simone Shevchuk   Structural hazard stall (mem_busy),
--                                  bus arbitration between IF and MEM. Other hazards
--     21 May 26  Simone Shevchuk   Add forwarding hold for EX stage
--     25 May 26  Simone Shevchuk   Update comments
----------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.InstructionConstants.all;

entity  SH2_CPU  is

    port (
        Reset   :  in     std_logic;
        NMI     :  in     std_logic;
        INT     :  in     std_logic;
        clock   :  in     std_logic;
        AB      :  out    std_logic_vector(31 downto 0);
        RE0     :  out    std_logic;
        RE1     :  out    std_logic;
        RE2     :  out    std_logic;
        RE3     :  out    std_logic;
        WE0     :  out    std_logic;
        WE1     :  out    std_logic;
        WE2     :  out    std_logic;
        WE3     :  out    std_logic;
        DB      :  inout  std_logic_vector(31 downto 0)
    );

end  SH2_CPU;

architecture structural of SH2_CPU is

    signal SR : std_logic_vector(31 downto 0) := (others => '0');

    -- Control unit signals from ID 
    signal s_IR             : std_logic_vector(15 downto 0);
    signal s_id_valid       : std_logic;
    signal s_reg_ALU_IN     : std_logic_vector(7 downto 0);
    signal s_reg_MAU        : std_logic_vector(16 downto 0);
    signal s_alu_IN         : std_logic_vector(1 downto 0);
    signal s_alu_gen        : std_logic_vector(10 downto 0);
    signal s_alu_sh2        : std_logic_vector(10 downto 0);
    signal s_dau_controls   : std_logic_vector(9 downto 0);
    signal s_dau_write      : std_logic_vector(1 downto 0);
    signal s_dau_out_sel    : std_logic_vector(1 downto 0);
    signal s_pau_controls   : std_logic_vector(5 downto 0);
    signal s_RE             : std_logic_vector(3 downto 0);
    signal s_WE             : std_logic_vector(3 downto 0);
    signal s_delay_slot     : std_logic;
    signal s_data_bus_sel   : std_logic_vector(1 downto 0);
    signal s_sign_zero_sel  : std_logic;
    signal s_tbit_write     : std_logic;
    signal s_imm_sel        : std_logic_vector(1 downto 0);
    signal s_alu_opa_zero   : std_logic;
    signal s_alu_opa_hold   : std_logic;
    signal s_alu_opb_bit7   : std_logic;
    signal s_dau_load_data  : std_logic;
    signal s_is_mem         : std_logic;
    signal s_is_load        : std_logic;
    signal s_is_rmw         : std_logic;
    signal s_is_branch      : std_logic;
    signal s_is_cond_branch : std_logic;
    signal s_is_BT          : std_logic;
    signal s_is_BF          : std_logic;

    -- Register file signals (reads in ID, writes from WB)
    signal s_reg_a          : std_logic_vector(31 downto 0);
    signal s_reg_b          : std_logic_vector(31 downto 0);
    signal s_reg_r0         : std_logic_vector(31 downto 0);
    signal s_reg_a2         : std_logic_vector(31 downto 0);
    signal s_reg_in         : std_logic_vector(31 downto 0);
    signal s_reg_ax_in      : std_logic_vector(31 downto 0);

    -- PAU signals
    signal s_pau_addr       : std_logic_vector(31 downto 0);
    signal s_pau_pc         : std_logic_vector(31 downto 0);
    signal s_pr             : std_logic_vector(31 downto 0);

    -- EX stage combinational signals
    signal s_ext_imm        : std_logic_vector(31 downto 0);
    signal s_ext_sz_imm     : std_logic_vector(31 downto 0);
    signal s_alu_opa        : std_logic_vector(31 downto 0);
    signal s_alu_opb        : std_logic_vector(31 downto 0);
    signal s_alu_result     : std_logic_vector(31 downto 0);
    signal s_tbit           : std_logic;
    signal s_dau_addr       : std_logic_vector(31 downto 0);
    signal s_dau_addr_wb    : std_logic_vector(31 downto 0);
    signal s_dau_out        : std_logic_vector(31 downto 0);
    signal s_store_data     : std_logic_vector(31 downto 0);

    -- Pipeline control signals
    signal stall_IF         : std_logic;
    signal stall_ID         : std_logic;
    signal flush_IF         : std_logic;
    signal bubble_EX        : std_logic;
    signal bubble_mem       : std_logic;
    signal mem_busy         : std_logic;
    signal load_use_hazard  : std_logic;
    signal s_branch_taken   : std_logic;

    -- Forwarding mux outputs (replace raw pipeline register values in EX)
    signal fwd_reg_a        : std_logic_vector(31 downto 0);
    signal fwd_reg_b        : std_logic_vector(31 downto 0);
    signal fwd_reg_r0       : std_logic_vector(31 downto 0);
    signal fwd_reg_a2       : std_logic_vector(31 downto 0);
    signal fwd_tbit         : std_logic;

    -- Forwarding value from each stage (what would be written to rd)
    signal mem_fwd_rd       : std_logic_vector(31 downto 0);
    signal wb_fwd_rd        : std_logic_vector(31 downto 0);

    -- Extracted register index aliases for forwarding comparisons
    signal ex_rs_a          : std_logic_vector(3 downto 0);
    signal ex_rs_b          : std_logic_vector(3 downto 0);
    signal ex_rs_a2         : std_logic_vector(3 downto 0);
    -- MEM destination
    signal mem_rd_sel       : std_logic_vector(3 downto 0);
    signal mem_rd_write     : std_logic;
    signal mem_rax_sel      : std_logic_vector(3 downto 0);
    signal mem_rax_write    : std_logic;
    -- WB destination
    signal wb_rd_sel        : std_logic_vector(3 downto 0);
    signal wb_rd_write      : std_logic;
    signal wb_rax_sel       : std_logic_vector(3 downto 0);
    signal wb_rax_write     : std_logic;
    -- ID source registers (for load-use hazard, from current control unit decode)
    signal id_rs_a          : std_logic_vector(3 downto 0);
    signal id_rs_b          : std_logic_vector(3 downto 0);
    signal id_rs_a2         : std_logic_vector(3 downto 0);
    signal id_uses_r0       : std_logic;
    -- EX load destination (for load-use hazard)
    signal ex_rd_sel        : std_logic_vector(3 downto 0);

    -- WB-to-ID bypass (same-cycle register write/read)
    signal id_bypass_a      : std_logic_vector(31 downto 0);
    signal id_bypass_b      : std_logic_vector(31 downto 0);
    signal id_bypass_r0     : std_logic_vector(31 downto 0);
    signal id_bypass_a2     : std_logic_vector(31 downto 0);

    -- Bus mux signals
    signal s_ab_out         : std_logic_vector(31 downto 0);
    signal s_re_out         : std_logic_vector(3 downto 0);
    signal s_we_out         : std_logic_vector(3 downto 0);

    -- EX pipeline register (ID/EX: consumed in EX stage)
    signal ex_valid         : std_logic := '0';
    signal ex_IR            : std_logic_vector(15 downto 0);
    signal ex_reg_a         : std_logic_vector(31 downto 0);
    signal ex_reg_b         : std_logic_vector(31 downto 0);
    signal ex_reg_r0        : std_logic_vector(31 downto 0);
    signal ex_reg_a2        : std_logic_vector(31 downto 0);
    signal ex_reg_ALU_IN    : std_logic_vector(7 downto 0);
    signal ex_reg_MAU       : std_logic_vector(16 downto 0);
    signal ex_alu_IN        : std_logic_vector(1 downto 0);
    signal ex_alu_gen       : std_logic_vector(10 downto 0);
    signal ex_alu_sh2       : std_logic_vector(10 downto 0);
    signal ex_dau_controls  : std_logic_vector(9 downto 0);
    signal ex_dau_write     : std_logic_vector(1 downto 0);
    signal ex_dau_out_sel   : std_logic_vector(1 downto 0);
    signal ex_pau_controls  : std_logic_vector(5 downto 0);
    signal ex_RE            : std_logic_vector(3 downto 0);
    signal ex_WE            : std_logic_vector(3 downto 0);
    signal ex_data_bus_sel  : std_logic_vector(1 downto 0);
    signal ex_sign_zero_sel : std_logic;
    signal ex_imm_sel       : std_logic_vector(1 downto 0);
    signal ex_tbit_write    : std_logic;
    signal ex_alu_opa_zero  : std_logic;
    signal ex_alu_opa_hold  : std_logic;
    signal ex_alu_opb_bit7  : std_logic;
    signal ex_dau_load_data : std_logic;
    signal ex_is_mem        : std_logic;
    signal ex_is_load       : std_logic;
    signal ex_is_rmw        : std_logic;
    signal ex_is_branch     : std_logic;
    signal ex_is_cond_branch: std_logic;
    signal ex_delay_slot    : std_logic;
    signal ex_is_BT         : std_logic;
    signal ex_is_BF         : std_logic;
    signal ex_pr_val        : std_logic_vector(31 downto 0);
    signal ex_sr_val        : std_logic_vector(31 downto 0);
    signal ex_sr_fwd        : std_logic_vector(31 downto 0);

    -- MEM pipeline register (EX/MEM: consumed in MEM stage)
    signal mem_valid        : std_logic := '0';
    signal mem_alu_result   : std_logic_vector(31 downto 0);
    signal mem_tbit         : std_logic;
    signal mem_tbit_write   : std_logic;
    signal mem_dau_addr     : std_logic_vector(31 downto 0);
    signal mem_dau_addr_wb  : std_logic_vector(31 downto 0);
    signal mem_dau_out      : std_logic_vector(31 downto 0);
    signal mem_RE           : std_logic_vector(3 downto 0);
    signal mem_WE           : std_logic_vector(3 downto 0);
    signal mem_is_mem       : std_logic;
    signal mem_is_load      : std_logic;
    signal mem_data_bus_sel : std_logic_vector(1 downto 0);
    signal mem_store_data   : std_logic_vector(31 downto 0);
    signal mem_reg_ALU_IN   : std_logic_vector(7 downto 0);
    signal mem_reg_MAU      : std_logic_vector(16 downto 0);
    signal mem_dau_write    : std_logic_vector(1 downto 0);
    signal mem_dau_out_sel  : std_logic_vector(1 downto 0);
    signal mem_dau_load_data: std_logic;
    signal mem_return_addr  : std_logic_vector(31 downto 0);
    signal mem_pau_pr_sel   : std_logic_vector(1 downto 0);
    signal mem_pr_val       : std_logic_vector(31 downto 0);
    signal mem_sr_val       : std_logic_vector(31 downto 0);
    signal mem_is_rmw       : std_logic;

    -- WB pipeline register (MEM/WB: consumed in WB stage)
    signal wb_valid         : std_logic := '0';
    signal wb_alu_result    : std_logic_vector(31 downto 0);
    signal wb_mem_data      : std_logic_vector(31 downto 0);
    signal wb_tbit          : std_logic;
    signal wb_tbit_write    : std_logic;
    signal wb_dau_addr_wb   : std_logic_vector(31 downto 0);
    signal wb_dau_out       : std_logic_vector(31 downto 0);
    signal wb_reg_ALU_IN    : std_logic_vector(7 downto 0);
    signal wb_reg_MAU       : std_logic_vector(16 downto 0);
    signal wb_dau_write     : std_logic_vector(1 downto 0);
    signal wb_dau_out_sel   : std_logic_vector(1 downto 0);
    signal wb_dau_load_data : std_logic;
    signal wb_return_addr   : std_logic_vector(31 downto 0);
    signal wb_pau_pr_sel    : std_logic_vector(1 downto 0);
    signal wb_is_load       : std_logic;
    signal wb_pr_val        : std_logic_vector(31 downto 0);
    signal wb_sr_val        : std_logic_vector(31 downto 0);

    -- WB stage derived signals
    signal wb_reg_in_sel    : std_logic_vector(2 downto 0);
    signal wb_ext_tbit      : std_logic_vector(31 downto 0);
    signal s_pr_sel         : integer range 3 downto 0;
    signal s_pr_src         : std_logic_vector(31 downto 0);
    signal s_dau_write_data : std_logic_vector(31 downto 0);

    -- RMW FSM signals (multi-cycle read-modify-write in MEM stage)
    type rmw_state_type is (RMW_IDLE, RMW_READ);
    signal rmw_phase        : rmw_state_type := RMW_IDLE;
    signal rmw_entering     : std_logic;
    signal rmw_active       : std_logic;
    signal stall_EX         : std_logic;
    signal db_hold           : std_logic_vector(7 downto 0);
    signal rmw_byte_result  : std_logic_vector(7 downto 0);
    signal rmw_tbit_result  : std_logic;
    signal rmw_write_data   : std_logic_vector(31 downto 0);
    signal mem_rmw_opb      : std_logic_vector(7 downto 0);
    signal mem_rmw_f_cmd    : std_logic_vector(3 downto 0);
    signal mem_alu_opb_bit7 : std_logic;

    -- Special register hazard signals (GBR/VBR/PR stalling)
    signal id_uses_gbr         : std_logic;
    signal id_uses_vbr         : std_logic;
    signal id_reads_pr         : std_logic;
    signal gbr_hazard          : std_logic;
    signal vbr_hazard          : std_logic;
    signal pr_hazard           : std_logic;
    signal pr_write_in_flight  : std_logic;
    signal special_reg_hazard  : std_logic;
    signal id_bypass_pr        : std_logic_vector(31 downto 0);

begin

    -- EX choose how to sign extend immediate given the EX imm sel signal that 
    -- propogates from the control unit, used in PAU and DAU same logic as unpiplined
    s_ext_imm <= (31 downto 4 => '0') & ex_IR(3 downto 0)          when ex_imm_sel = "01" else
                 (31 downto 12 => ex_IR(11)) & ex_IR(11 downto 0)   when ex_imm_sel = "10" else
                 (31 downto 8 => '0') & ex_IR(7 downto 0)           when ex_imm_sel = "11" else
                 (31 downto 8 => ex_IR(7)) & ex_IR(7 downto 0);

    -- Register index extraction (for forwarding and hazard comparisons), need a
    -- lot more extractions since can be different for each stage and need to do them
    -- ahead of time for forwarding and hazard control.
    -- EX source register indices
    ex_rs_a   <= ex_reg_MAU(REG_MAU_A_SEL_IDX downto REG_MAU_B_SEL_IDX+1);   
    ex_rs_b   <= ex_reg_MAU(REG_MAU_B_SEL_IDX downto REG_MAU_AX_SEL_IDX+1);  
    ex_rs_a2  <= ex_reg_MAU(REG_MAU_A2_SEL_IDX downto 0);                    
    ex_rd_sel <= ex_reg_ALU_IN(REG_IN_SEL_IDX downto REG_STORE_IDX+1);       
    -- MEM destination register indices
    mem_rd_sel   <= mem_reg_ALU_IN(REG_IN_SEL_IDX downto REG_STORE_IDX+1);    
    mem_rd_write <= mem_reg_ALU_IN(REG_STORE_IDX);                             
    mem_rax_sel  <= mem_reg_MAU(REG_MAU_AX_SEL_IDX downto REG_MAU_AX_STORE_IDX+1); 
    mem_rax_write <= mem_reg_MAU(REG_MAU_AX_STORE_IDX);                       
    -- WB destination register indices
    wb_rd_sel   <= wb_reg_ALU_IN(REG_IN_SEL_IDX downto REG_STORE_IDX+1);    
    wb_rd_write <= wb_reg_ALU_IN(REG_STORE_IDX);                             
    wb_rax_sel  <= wb_reg_MAU(REG_MAU_AX_SEL_IDX downto REG_MAU_AX_STORE_IDX+1); 
    wb_rax_write <= wb_reg_MAU(REG_MAU_AX_STORE_IDX);                        
    -- ID source register indices (current decode, for load-use hazard)
    id_rs_a   <= s_reg_MAU(REG_MAU_A_SEL_IDX downto REG_MAU_B_SEL_IDX+1); 
    id_rs_b   <= s_reg_MAU(REG_MAU_B_SEL_IDX downto REG_MAU_AX_SEL_IDX+1); 
    id_rs_a2  <= s_reg_MAU(REG_MAU_A2_SEL_IDX downto 0);                    
    -- R0 used implicitly when DAU offset_sel = "01" (R0 as address offset), so
    -- need to do a separate check since it is implicit
    id_uses_r0 <= '1' when s_dau_controls(DAU_OFFSET_SEL_IDX downto DAU_INC_DEC_SEL_IDX+1) = "01" else '0';


    -- Pipeline stall, flush, and hazard logic
    -- data bus (memory) is busy when an instructions sets is_mem and it is a valid instruction decode
    mem_busy  <= '1' when mem_is_mem = '1' and mem_valid = '1' else '0';

    -- Load-use hazard: there is a load in EX and a dependent instruction in ID
    -- loading in from memory detected in EX and the register that is being loaded into
    -- is stored and valid ID and new potentially dependent instruction also valid ID
    -- and the instruction in EX is same instruction being decoded input register a, 
    -- b, or a2 or using reg 0.
    load_use_hazard <= '1' when (ex_is_load = '1' and ex_reg_ALU_IN(REG_STORE_IDX) = '1'
                                 and ex_valid = '1' and s_id_valid = '1')
                                and (ex_rd_sel = id_rs_a or ex_rd_sel = id_rs_b
                                     or ex_rd_sel = id_rs_a2
                                     or (ex_rd_sel = "0000" and id_uses_r0 = '1'))
                       else '0';

    -- Branch resolution in EX: unconditional always taken, conditional checks T-bit
    -- We are taking the branch when valid instruction, it is a branch and it is 
    -- unconditional or the Tbit condition is met, this condition is checked with forwarded
    -- T bit value.
    s_branch_taken <= '1' when (ex_valid = '1' and ex_is_branch = '1'
                                and (ex_is_cond_branch = '0'
                                     or (ex_is_BT = '1' and fwd_tbit = '1')
                                     or (ex_is_BF = '1' and fwd_tbit = '0')))
                      else '0';

    -- RMW FSM control
    -- entering into the read modify write when in the mem stage and valid instruction
    rmw_entering <= '1' when (mem_is_rmw = '1' and mem_valid = '1' and rmw_phase = RMW_IDLE) else '0';
    -- active in the rmw when we have already entered and then in actively reading 
    rmw_active   <= '1' when (rmw_entering = '1' or rmw_phase = RMW_READ) else '0';
    -- we need to stall any other execution as we hit entering since RMW needs the 
    -- memory buses twice.
    stall_EX     <= rmw_entering;

    -- Special register hazard detection
    -- first figure out whether the instruction being decoded uses the vbr or gbr.
    id_uses_gbr <= '1' when (s_dau_controls(DAU_SRC_SEL_IDX downto DAU_SHIFT_SEL_IDX+1) = "01" or
                             s_dau_out_sel = "01")
                   else '0';
    id_uses_vbr <= '1' when (s_dau_controls(DAU_SRC_SEL_IDX downto DAU_SHIFT_SEL_IDX+1) = "10" or
                             s_dau_out_sel = "10")
                   else '0';

    -- now we can figure out if there is a hazard if ID instruction is valid and uses
    -- special register and either the instruction in exectution is writing to it or
    -- the instruction in mem phase is writing to it
    gbr_hazard <= '1' when (s_id_valid = '1' and id_uses_gbr = '1' and
                            ((ex_valid = '1' and ex_dau_write(DAU_WRITE_GBR_IDX) = '1') or
                             (mem_valid = '1' and mem_dau_write(DAU_WRITE_GBR_IDX) = '1')))
                  else '0';
    vbr_hazard <= '1' when (s_id_valid = '1' and id_uses_vbr = '1' and
                            ((ex_valid = '1' and ex_dau_write(DAU_WRITE_VBR_IDX) = '1') or
                             (mem_valid = '1' and mem_dau_write(DAU_WRITE_VBR_IDX) = '1')))
                  else '0';

    -- detetmine if instruction in ID needs PR, then determine if there is a 
    -- PR write that still needs to happen outside of the forwarding/bypass logic
    -- then can determine if there is actually a hazard. 
    id_reads_pr <= '1' when (s_pau_controls(PAU_SRC_SEL_IDX downto PAU_OFFSET_SEL_IDX+1) = "01" or
                             s_reg_ALU_IN(REG_IN_SRC_IDX downto REG_IN_SEL_IDX+1) = "011" or
                             s_data_bus_sel = "11")
                   else '0';
    pr_write_in_flight <= '1' when ((ex_valid = '1' and ex_pau_controls(PAU_PR_SEL_IDX downto 0) /= "00") or
                                     (mem_valid = '1' and mem_pau_pr_sel /= "00"))
                          else '0';
    pr_hazard <= '1' when (s_id_valid = '1' and id_reads_pr = '1' and pr_write_in_flight = '1')
                 else '0';

    special_reg_hazard <= gbr_hazard or vbr_hazard or pr_hazard;

    -- if the mem is busy we cannot do IF need to stall and if load_use hazard 
    -- rmw_active or special register hazard also need to stall since instruction
    -- dependent on the one using either the regisster or resource needs to wait 
    stall_IF   <= mem_busy or load_use_hazard or rmw_active or special_reg_hazard;
    -- if the mem is busy or rmw_active then can just stall the instruction decode
    stall_ID   <= mem_busy or rmw_active;
    -- need to flush the instruction fetch it is garbage if we are taking the branch
    flush_IF   <= s_branch_taken;
    -- need to buble if load use or special reg but not if mem_busy or rmw active 
    -- since those are handled by the stall
    -- need to bubble the EX if branch is taken and it is not a delay slot since
    -- we are two IF ahead so this is garbage
    bubble_EX  <= ((load_use_hazard or special_reg_hazard) and not mem_busy and not rmw_active)
                  or (s_branch_taken and not ex_delay_slot);
    bubble_mem <= mem_busy;

    -- Forwarding value computation
    -- Value that MEM stage instruction will write to its rd (not available for loads)
    -- same isignals as used before for register array input 
    mem_fwd_rd <= mem_alu_result                         when mem_reg_ALU_IN(REG_IN_SRC_IDX downto REG_IN_SEL_IDX+1) = "000" else
                  (31 downto 1 => '0') & mem_tbit        when mem_reg_ALU_IN(REG_IN_SRC_IDX downto REG_IN_SEL_IDX+1) = "010" else
                  mem_pr_val                             when mem_reg_ALU_IN(REG_IN_SRC_IDX downto REG_IN_SEL_IDX+1) = "011" else
                  mem_dau_out                            when mem_reg_ALU_IN(REG_IN_SRC_IDX downto REG_IN_SEL_IDX+1) = "100" else
                  mem_sr_val                             when mem_reg_ALU_IN(REG_IN_SRC_IDX downto REG_IN_SEL_IDX+1) = "101" else
                  mem_alu_result;

    -- Value that WB stage instruction will write to its rd (loads have mem_data available)
    wb_fwd_rd <= wb_alu_result                           when wb_reg_ALU_IN(REG_IN_SRC_IDX downto REG_IN_SEL_IDX+1) = "000" else
                 wb_mem_data                             when wb_reg_ALU_IN(REG_IN_SRC_IDX downto REG_IN_SEL_IDX+1) = "001" else
                 (31 downto 1 => '0') & wb_tbit          when wb_reg_ALU_IN(REG_IN_SRC_IDX downto REG_IN_SEL_IDX+1) = "010" else
                 wb_pr_val                               when wb_reg_ALU_IN(REG_IN_SRC_IDX downto REG_IN_SEL_IDX+1) = "011" else
                 wb_dau_out                              when wb_reg_ALU_IN(REG_IN_SRC_IDX downto REG_IN_SEL_IDX+1) = "100" else
                 wb_sr_val                               when wb_reg_ALU_IN(REG_IN_SRC_IDX downto REG_IN_SEL_IDX+1) = "101" else
                 wb_alu_result;

    -- Forwarding muxes (priority: MEM rd > MEM ax > WB rd > WB ax > pipeline reg)
    fwd_reg_a <= mem_fwd_rd      when (mem_valid = '1' and mem_rd_write = '1' and mem_is_load = '0' and mem_rd_sel = ex_rs_a) else
                 mem_dau_addr_wb when (mem_valid = '1' and mem_rax_write = '1' and mem_rax_sel = ex_rs_a) else
                 wb_fwd_rd       when (wb_valid = '1' and wb_rd_write = '1' and wb_rd_sel = ex_rs_a) else
                 wb_dau_addr_wb  when (wb_valid = '1' and wb_rax_write = '1' and wb_rax_sel = ex_rs_a) else
                 ex_reg_a;

    fwd_reg_b <= mem_fwd_rd      when (mem_valid = '1' and mem_rd_write = '1' and mem_is_load = '0' and mem_rd_sel = ex_rs_b) else
                 mem_dau_addr_wb when (mem_valid = '1' and mem_rax_write = '1' and mem_rax_sel = ex_rs_b) else
                 wb_fwd_rd       when (wb_valid = '1' and wb_rd_write = '1' and wb_rd_sel = ex_rs_b) else
                 wb_dau_addr_wb  when (wb_valid = '1' and wb_rax_write = '1' and wb_rax_sel = ex_rs_b) else
                 ex_reg_b;

    fwd_reg_r0 <= mem_fwd_rd      when (mem_valid = '1' and mem_rd_write = '1' and mem_is_load = '0' and mem_rd_sel = "0000") else
                  mem_dau_addr_wb when (mem_valid = '1' and mem_rax_write = '1' and mem_rax_sel = "0000") else
                  wb_fwd_rd       when (wb_valid = '1' and wb_rd_write = '1' and wb_rd_sel = "0000") else
                  wb_dau_addr_wb  when (wb_valid = '1' and wb_rax_write = '1' and wb_rax_sel = "0000") else
                  ex_reg_r0;

    fwd_reg_a2 <= mem_fwd_rd      when (mem_valid = '1' and mem_rd_write = '1' and mem_is_load = '0' and mem_rd_sel = ex_rs_a2) else
                  mem_dau_addr_wb when (mem_valid = '1' and mem_rax_write = '1' and mem_rax_sel = ex_rs_a2) else
                  wb_fwd_rd       when (wb_valid = '1' and wb_rd_write = '1' and wb_rd_sel = ex_rs_a2) else
                  wb_dau_addr_wb  when (wb_valid = '1' and wb_rax_write = '1' and wb_rax_sel = ex_rs_a2) else
                  ex_reg_a2;

    -- T-bit forwarding (for ADDC/SUBC/ROTCL/ROTCR carry input and branch condition)
    fwd_tbit <= mem_tbit when (mem_tbit_write = '1' and mem_valid = '1') else
                wb_tbit  when (wb_tbit_write = '1' and wb_valid = '1') else
                SR(0);

    -- SR forwarding: replace stale T-bit in latched SR with forwarded T-bit
    ex_sr_fwd <= ex_sr_val(31 downto 1) & fwd_tbit;

    -- WB-to-ID bypass: when WB writes a register in the same cycle that ID
    -- reads it, the register file read returns the pre-write (stale) value.
    -- These muxes forward the WB write data directly into the ID->EX latch.
    id_bypass_a  <= wb_fwd_rd      when (wb_valid = '1' and wb_rd_write = '1' and wb_rd_sel = id_rs_a) else
                    wb_dau_addr_wb when (wb_valid = '1' and wb_rax_write = '1' and wb_rax_sel = id_rs_a) else
                    s_reg_a;

    id_bypass_b  <= wb_fwd_rd      when (wb_valid = '1' and wb_rd_write = '1' and wb_rd_sel = id_rs_b) else
                    wb_dau_addr_wb when (wb_valid = '1' and wb_rax_write = '1' and wb_rax_sel = id_rs_b) else
                    s_reg_b;

    id_bypass_r0 <= wb_fwd_rd      when (wb_valid = '1' and wb_rd_write = '1' and wb_rd_sel = "0000") else
                    wb_dau_addr_wb when (wb_valid = '1' and wb_rax_write = '1' and wb_rax_sel = "0000") else
                    s_reg_r0;

    id_bypass_a2 <= wb_fwd_rd      when (wb_valid = '1' and wb_rd_write = '1' and wb_rd_sel = id_rs_a2) else
                    wb_dau_addr_wb when (wb_valid = '1' and wb_rax_write = '1' and wb_rax_sel = id_rs_a2) else
                    s_reg_a2;

    -- PR WB-to-ID bypass: forward PR write from WB to ID
    id_bypass_pr <= s_pr_src when (wb_valid = '1' and wb_pau_pr_sel /= "00") else s_pr;

    -- RMW byte computation in MEM stage
    rmw_byte_result <= (db_hold and mem_rmw_opb) when mem_rmw_f_cmd = "1000" else
                       (db_hold or  mem_rmw_opb) when mem_rmw_f_cmd = "1110" else
                       (db_hold xor mem_rmw_opb);

    rmw_tbit_result <= '1' when (mem_alu_opb_bit7 = '1' and db_hold = x"00") else
                       '1' when (mem_alu_opb_bit7 = '0' and (db_hold and mem_rmw_opb) = x"00") else
                       '0';

    rmw_write_data <= x"000000" & rmw_byte_result;

    -- Bus muxing, RMW write > RMW read > normal MEM > IF
    s_ab_out <= mem_dau_addr when (mem_busy = '1' or rmw_active = '1') else s_pau_addr;

    s_re_out <= RE_NONE  when rmw_phase = RMW_READ else
                mem_RE   when mem_busy = '1' else
                RE_LONG;

    s_we_out <= mem_WE   when rmw_phase = RMW_READ else
                WE_NONE  when rmw_entering = '1' else
                mem_WE   when mem_busy = '1' else
                WE_NONE;

    -- Address bus mux (tri-state during reset so TB can load program)
    AB <= (others => 'Z') when Reset = '0' else s_ab_out;

    -- Data bus mux (tri-state during reset and when not writing)
    DB <= (others => 'Z') when (Reset = '0' or s_we_out = WE_NONE) else
          rmw_write_data   when rmw_phase = RMW_READ else
          mem_store_data;

    -- RE/WE gated with clock
    RE0 <= 'Z' when Reset = '0' else (s_re_out(0) or clock);
    RE1 <= 'Z' when Reset = '0' else (s_re_out(1) or clock);
    RE2 <= 'Z' when Reset = '0' else (s_re_out(2) or clock);
    RE3 <= 'Z' when Reset = '0' else (s_re_out(3) or clock);
    WE0 <= 'Z' when Reset = '0' else (s_we_out(0) or clock);
    WE1 <= 'Z' when Reset = '0' else (s_we_out(1) or clock);
    WE2 <= 'Z' when Reset = '0' else (s_we_out(2) or clock);
    WE3 <= 'Z' when Reset = '0' else (s_we_out(3) or clock);

    -- SR register (T-bit written from WB)
    process(clock)
    begin
        if rising_edge(clock) then
            if Reset = '0' then
                SR <= (31 downto 10 => '0') & "00" & "1111" & (3 downto 0 => '0');
            elsif wb_tbit_write = '1' and wb_valid = '1' then
                SR(0) <= wb_tbit;
            end if;
        end if;
    end process;

    -- RMW FSM sequences byte read then write in MEM stage
    process(clock)
    begin
        if rising_edge(clock) then
            if Reset = '0' then
                rmw_phase <= RMW_IDLE;
                db_hold <= (others => '0');
            else
                case rmw_phase is
                    when RMW_IDLE =>
                        if mem_is_rmw = '1' and mem_valid = '1' then
                            db_hold <= DB(7 downto 0);
                            rmw_phase <= RMW_READ;
                        end if;
                    when RMW_READ =>
                        rmw_phase <= RMW_IDLE;
                end case;
            end if;
        end if;
    end process;

    -- Control Unit (ID stage: IR latch + combinational decode)
    ControlUnit : entity work.ControlSH2
        port map (
            DB              => DB,
            addr_bit1       => s_pau_addr(1),
            clock           => clock,
            reset           => Reset,
            stall_IF        => stall_IF,
            flush_IF        => flush_IF,
            IR              => s_IR,
            id_valid        => s_id_valid,
            reg_ALU_IN      => s_reg_ALU_IN,
            reg_MAU         => s_reg_MAU,
            alu_IN          => s_alu_IN,
            alu_gen         => s_alu_gen,
            alu_sh2         => s_alu_sh2,
            dau_controls    => s_dau_controls,
            dau_write       => s_dau_write,
            dau_out_sel     => s_dau_out_sel,
            pau_controls    => s_pau_controls,
            RE              => s_RE,
            WE              => s_WE,
            delay_slot      => s_delay_slot,
            data_bus_sel    => s_data_bus_sel,
            sign_zero_ALU_sel => s_sign_zero_sel,
            tbit_write      => s_tbit_write,
            imm_sel         => s_imm_sel,
            alu_opa_zero    => s_alu_opa_zero,
            alu_opa_hold    => s_alu_opa_hold,
            alu_opb_bit7    => s_alu_opb_bit7,
            dau_load_data   => s_dau_load_data,
            is_mem          => s_is_mem,
            is_load         => s_is_load,
            is_rmw          => s_is_rmw,
            is_branch       => s_is_branch,
            is_cond_branch  => s_is_cond_branch,
            is_BT           => s_is_BT,
            is_BF           => s_is_BF
        );

    -- Register Array (reads combinational in ID, writes clocked from WB)
    wb_reg_in_sel <= wb_reg_ALU_IN(REG_IN_SRC_IDX downto REG_IN_SEL_IDX+1); -- select for which source to write to register file
    wb_ext_tbit   <= (31 downto 1 => '0') & wb_tbit;

    s_reg_in <= wb_alu_result  when wb_reg_in_sel = "000" else
                wb_mem_data    when wb_reg_in_sel = "001" else
                wb_ext_tbit    when wb_reg_in_sel = "010" else
                wb_pr_val      when wb_reg_in_sel = "011" else
                wb_dau_out     when wb_reg_in_sel = "100" else
                wb_sr_val      when wb_reg_in_sel = "101" else
                (others => '0');

    s_reg_ax_in <= wb_dau_addr_wb; -- for instructions that write to address register for updates, value always comes from data bus

    RegArray : entity work.RegArrSH2
        port map (
            clock       => clock,
            reg_in      => s_reg_in,
            reg_in_sel  => to_integer(unsigned(wb_reg_ALU_IN(REG_IN_SEL_IDX downto REG_STORE_IDX+1))),
            reg_store   => wb_reg_ALU_IN(REG_STORE_IDX) and wb_valid,
            reg_a_sel   => to_integer(unsigned(s_reg_MAU(REG_MAU_A_SEL_IDX downto REG_MAU_B_SEL_IDX+1))),
            reg_b_sel   => to_integer(unsigned(s_reg_MAU(REG_MAU_B_SEL_IDX downto REG_MAU_AX_SEL_IDX+1))),
            reg_ax_in   => s_reg_ax_in,
            reg_ax_sel  => to_integer(unsigned(wb_reg_MAU(REG_MAU_AX_SEL_IDX downto REG_MAU_AX_STORE_IDX+1))),
            reg_ax_store => wb_reg_MAU(REG_MAU_AX_STORE_IDX) and wb_valid,
            reg_a2_sel  => to_integer(unsigned(s_reg_MAU(REG_MAU_A2_SEL_IDX downto 0))),
            reg_a       => s_reg_a,
            reg_b       => s_reg_b,
            reg_a1      => s_reg_r0,
            reg_a2      => s_reg_a2
        );

    -- PAU (IF stage address output, branch target computation from EX)
    PAU : entity work.PAUSH2
        port map (
            clock        => clock,
            reset        => Reset,
            src_sel      => to_integer(unsigned(ex_pau_controls(PAU_SRC_SEL_IDX downto PAU_OFFSET_SEL_IDX+1))),
            addr_off     => s_ext_imm,
            addr_reg     => fwd_reg_a,
            offset_sel   => to_integer(unsigned(ex_pau_controls(PAU_OFFSET_SEL_IDX downto PAU_PR_SEL_IDX+1))),
            branch_taken => s_branch_taken,
            stall        => stall_IF,
            pr_sel       => s_pr_sel,
            pr_src       => s_pr_src,
            address_out  => s_pau_addr,
            PC_out       => s_pau_pc,
            PR           => s_pr
        );


    -- DAU (address computation in EX, GBR/VBR writes from WB)
    s_dau_write_data <= wb_mem_data   when wb_dau_load_data = '1' else wb_alu_result;

    DAU : entity work.DAUSH2
        port map (
            addr_PC       => s_pau_pc, -- gets direct line from PAU
            addr_reg      => fwd_reg_a2,
            src_sel       => to_integer(unsigned(ex_dau_controls(DAU_SRC_SEL_IDX downto DAU_SHIFT_SEL_IDX+1))),
            shift_sel     => to_integer(unsigned(ex_dau_controls(DAU_SHIFT_SEL_IDX downto DAU_OFFSET_SEL_IDX+1))),
            offset_ins    => s_ext_imm,
            offset_reg    => fwd_reg_r0,
            offset_sel    => to_integer(unsigned(ex_dau_controls(DAU_OFFSET_SEL_IDX downto DAU_INC_DEC_SEL_IDX+1))),
            inc_dec_sel   => ex_dau_controls(DAU_INC_DEC_SEL_IDX),
            inc_dec_bit   => to_integer(unsigned(ex_dau_controls(DAU_INC_DEC_BIT_IDX downto DAU_PRE_POST_SEL_IDX+1))),
            pre_post_sel  => ex_dau_controls(DAU_PRE_POST_SEL_IDX),
            clock         => clock,
            reset         => Reset,
            gbr_write     => wb_dau_write(DAU_WRITE_GBR_IDX) and wb_valid,
            vbr_write     => wb_dau_write(DAU_WRITE_VBR_IDX) and wb_valid,
            write_data    => s_dau_write_data,
            data_out_sel  => to_integer(unsigned(ex_dau_out_sel)),
            address_out   => s_dau_addr,
            addr_src_out  => s_dau_addr_wb,
            data_out      => s_dau_out
        );


    -- ALU (computation in EX stage, inputs from ex_ pipeline register)
    s_ext_sz_imm <= (31 downto 8 => ex_IR(7)) & ex_IR(7 downto 0)  when ex_sign_zero_sel = '1' else
                    (31 downto 8 => '0') & ex_IR(7 downto 0);

    s_alu_opa <= (others => '0')       when ex_alu_opa_zero = '1' else
                 fwd_reg_a             when ex_alu_IN(ALU_SEL_A_IDX) = '1' else
                 (others => '0');

    s_alu_opb <= x"00000080"     when ex_alu_opb_bit7 = '1' else
                 (others => '0') when (ex_alu_gen(10) = ex_alu_gen(9) and ex_alu_gen(8) = ex_alu_gen(7) and ex_alu_sh2(ALU_RES_SEL_IDX downto ALU_T_SEL_IDX+1) = "000") else
                 fwd_reg_b       when ex_alu_IN(ALU_SEL_B_IDX) = '0' else
                 s_ext_sz_imm;

    ALU : entity work.ALUSH2
        port map (
            alu_opa   => s_alu_opa,
            alu_opb   => s_alu_opb,
            c_in      => fwd_tbit,
            f_cmd     => ex_alu_gen(ALU_F_CMD_IDX downto ALU_C_IN_CMD_IDX+1),
            c_in_cmd  => ex_alu_gen(ALU_C_IN_CMD_IDX downto ALU_S_CMD_IDX+1),
            s_cmd     => ex_alu_gen(ALU_S_CMD_IDX downto ALU_ALU_CMD_IDX+1),
            alu_cmd   => ex_alu_gen(ALU_ALU_CMD_IDX downto 0),
            shift_sel => to_integer(unsigned(ex_alu_sh2(ALU_SHIFT_SEL_IDX downto ALU_EXTEND_SEL_IDX+1))),
            extend_sel => ex_alu_sh2(ALU_EXTEND_SEL_IDX downto ALU_RES_SEL_IDX+1),
            res_sel   => to_integer(unsigned(ex_alu_sh2(ALU_RES_SEL_IDX downto ALU_T_SEL_IDX+1))),
            t_sel     => ex_alu_sh2(ALU_T_SEL_IDX downto 0),
            res       => s_alu_result,
            t_bit     => s_tbit
        );

    -- EX stage compute store data (selects what goes on DB during MEM store)
    s_store_data <= s_alu_result when ex_data_bus_sel = "00" else
                    s_dau_out    when ex_data_bus_sel = "01" else
                    ex_sr_fwd    when ex_data_bus_sel = "10" else
                    ex_pr_val;

    -- ID to EX pipeline register latch
    process(clock)
    begin
        if rising_edge(clock) then
            if Reset = '0' then
                ex_valid <= '0';
            elsif stall_ID = '1' then
                -- Re-capture forwarded register values so they survive WB moving forward
                ex_reg_a  <= fwd_reg_a;
                ex_reg_b  <= fwd_reg_b;
                ex_reg_r0 <= fwd_reg_r0;
                ex_reg_a2 <= fwd_reg_a2;
            elsif bubble_EX = '1' then
                ex_valid <= '0'; -- insert bubble (load-use hazard)
            else
                ex_valid         <= s_id_valid;
                ex_IR            <= s_IR;
                ex_reg_a         <= id_bypass_a;
                ex_reg_b         <= id_bypass_b;
                ex_reg_r0        <= id_bypass_r0;
                ex_reg_a2        <= id_bypass_a2;
                ex_reg_ALU_IN    <= s_reg_ALU_IN;
                ex_reg_MAU       <= s_reg_MAU;
                ex_alu_IN        <= s_alu_IN;
                ex_alu_gen       <= s_alu_gen;
                ex_alu_sh2       <= s_alu_sh2;
                ex_dau_controls  <= s_dau_controls;
                ex_dau_write     <= s_dau_write;
                ex_dau_out_sel   <= s_dau_out_sel;
                ex_pau_controls  <= s_pau_controls;
                ex_RE            <= s_RE;
                ex_WE            <= s_WE;
                ex_data_bus_sel  <= s_data_bus_sel;
                ex_sign_zero_sel <= s_sign_zero_sel;
                ex_imm_sel       <= s_imm_sel;
                ex_tbit_write    <= s_tbit_write;
                ex_alu_opa_zero  <= s_alu_opa_zero;
                ex_alu_opa_hold  <= s_alu_opa_hold;
                ex_alu_opb_bit7  <= s_alu_opb_bit7;
                ex_dau_load_data <= s_dau_load_data;
                ex_is_mem        <= s_is_mem;
                ex_is_load       <= s_is_load;
                ex_is_rmw        <= s_is_rmw;
                ex_is_branch     <= s_is_branch;
                ex_is_cond_branch <= s_is_cond_branch;
                ex_delay_slot    <= s_delay_slot;
                ex_is_BT         <= s_is_BT;
                ex_is_BF         <= s_is_BF;
                ex_pr_val        <= id_bypass_pr;
                ex_sr_val        <= SR;
            end if;
        end if;
    end process;

    -- EX to MEM pipeline register latch
    process(clock)
    begin
        if rising_edge(clock) then
            if Reset = '0' then
                mem_valid <= '0';
            elsif stall_EX = '1' then
                null;  -- hold all mem_ values (RMW keeps instruction in MEM)
            elsif bubble_mem = '1' then
                mem_valid <= '0';  -- insert bubble (MEM slot consumed by current mem op)
            else
                mem_valid         <= ex_valid;
                mem_alu_result    <= s_alu_result;
                mem_tbit          <= s_tbit;
                mem_tbit_write    <= ex_tbit_write;
                mem_dau_addr      <= s_dau_addr;
                mem_dau_addr_wb   <= s_dau_addr_wb;
                mem_dau_out       <= s_dau_out;
                mem_RE            <= ex_RE;
                mem_WE            <= ex_WE;
                mem_is_mem        <= ex_is_mem;
                mem_is_load       <= ex_is_load;
                mem_data_bus_sel  <= ex_data_bus_sel;
                mem_store_data    <= s_store_data;
                mem_reg_ALU_IN    <= ex_reg_ALU_IN;
                mem_reg_MAU       <= ex_reg_MAU;
                mem_dau_write     <= ex_dau_write;
                mem_dau_out_sel   <= ex_dau_out_sel;
                mem_dau_load_data <= ex_dau_load_data;
                mem_return_addr   <= s_pau_pc;  -- capture live PC as return address
                mem_pau_pr_sel    <= ex_pau_controls(PAU_PR_SEL_IDX downto 0);
                mem_pr_val        <= ex_pr_val;
                mem_sr_val        <= ex_sr_fwd;
                mem_is_rmw        <= ex_is_rmw;
                mem_rmw_opb       <= s_alu_opb(7 downto 0);
                mem_rmw_f_cmd     <= ex_alu_gen(ALU_F_CMD_IDX downto ALU_C_IN_CMD_IDX+1);
                mem_alu_opb_bit7  <= ex_alu_opb_bit7;
            end if;
        end if;
    end process;

    -- MEM to WB pipeline register latch
    process(clock)
    begin
        if rising_edge(clock) then
            if Reset = '0' then
                wb_valid <= '0';
            elsif rmw_entering = '1' then
                wb_valid <= '0';  -- RMW read phase suppress WB until RMW completes
            else
                wb_valid         <= mem_valid;
                wb_alu_result    <= mem_alu_result;
                if rmw_phase = RMW_READ then
                    wb_tbit <= rmw_tbit_result;
                else
                    wb_tbit <= mem_tbit;
                end if;
                wb_tbit_write    <= mem_tbit_write;
                wb_dau_addr_wb   <= mem_dau_addr_wb;
                wb_dau_out       <= mem_dau_out;
                wb_reg_ALU_IN    <= mem_reg_ALU_IN;
                wb_reg_MAU       <= mem_reg_MAU;
                wb_dau_write     <= mem_dau_write;
                wb_dau_out_sel   <= mem_dau_out_sel;
                wb_dau_load_data <= mem_dau_load_data;
                wb_return_addr   <= mem_return_addr;
                wb_pau_pr_sel    <= mem_pau_pr_sel;
                wb_is_load       <= mem_is_load;
                wb_pr_val        <= mem_pr_val;
                wb_sr_val        <= mem_sr_val;
                -- sign-extend loaded data from memory based on read size
                if mem_is_mem = '1' and mem_valid = '1' and mem_WE = WE_NONE and rmw_phase /= RMW_READ then
                    if mem_RE = RE_BYTE then
                        wb_mem_data <= (31 downto 8 => DB(7)) & DB(7 downto 0);
                    elsif mem_RE = RE_WORD then
                        wb_mem_data <= (31 downto 16 => DB(15)) & DB(15 downto 0);
                    else
                        wb_mem_data <= DB;
                    end if;
                else
                    wb_mem_data <= DB;
                end if;
            end if;
        end if;
    end process;

    -- WB stage PR write logic (pr_sel=0 means no write)
    s_pr_sel       <= to_integer(unsigned(wb_pau_pr_sel)) when wb_valid = '1' else 0;
    s_pr_src       <= wb_return_addr when wb_pau_pr_sel = "01" else
                      wb_alu_result  when wb_pau_pr_sel = "10" else
                      wb_mem_data;

end architecture structural;
