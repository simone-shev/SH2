----------------------------------------------------------------------------
--
--  Segmented MMU
--
--  This is an implementation of a segmented MMU. It divides memorry into 
--  segments each of which is a power of 2 in size (at least 2^10 or 1024 words). 
--  Each segment is mapped to a block of physical addresses that is also a power 
--  of 2 in size. The logical address space has 32 bits of address and the 
--  physical address space has 42 bits of address. The MMU does not need 
--  to access the external segment table. The CPU/OS will load the MMU registers 
--  (cache) with values from that table as needed.
--
--  Entities included are:
--     MMU  - The segmented MMU
--
--  Revision History:
--     28 May 26 Simone Shevchuk       Initial revision.
--     29 May 26 Simone Shevchuk       Update DB and status registers only 
--                                     driven in clocked processes and update 
--                                     register write from CPU/OS
----------------------------------------------------------------------------

--
--  MMU
--
--  MMU with 4 segments. Each segment is a power of 2 in size and is mapped to a 
--  block of physical addresses that is also a power of 2 in size. LAB gives the 
--  32-bit logical address and the MMU produces the 42-bit physical address, PAB.
--  The MMU also has a RW signal, high for read low for write and a chip select
--  signal CS, active low, for when the MMU is being accessed for register read/writes.
-- 
--  Each of the 4 sets of segment registers has 4 32-bit registers: a 22-bit logical address 
--  mask which defines the segment size, a 22-bit starting logical address which
--  when combined with the mask gives the segment number, a 32-bit starting 
--  physical address, and a 16-bit segment index that gives the entry number in 
--  the segment table combined with five bits of status. The physical address
--  is stored at offset 0, the logical address at offset 1, the mask at offset 2, 
--  and the index and status at offset 3 within each set of segment registers. 
--
--  The segment registers can be overwritten by the CPU/OS as needed. This is 
--  done using the WR signal and with data along the 32 bit DB. The 
--  low 4 bits of the LAB are used to determione which register to write to 
--  with bits 3 and 2 determining which set of segment registers and bits 1 and 
--  0 determining which register within that set. 
--
--  When the MMU, not updating, receives a logival address, it checks the top 
--  22 bits of the logical address against each segment registers' mask and the 
--  segment registerts' starting logical address and mask to determine which 
--  segment, if any, the address is in. If the address is in a valid segment, 
--  the MMU produces the physical address by taking the offset (at least the low
--  10 bits of the logical address but found fully through using the inverse mask) 
--  and concatenating it with the starting physical address from the segment 
--  register. If the address is not in a valid segment, the MMU produces a SegFault
--  signal. A ProtFault signal is producced is when the RW signal is low, for write
--  but the segment is write protected, the WP bit (29) is high. This also sets
--  the F bit (28) to indicate a fault. 
--
--  On any successful matching to a segment, the U bit(31) is set. On a 
--  successful write, the D bit (30) is set. 
--
--  Inputs:
--    RW      - high for read, low for write
--    LAB     - logical address bus (32 bits)
--    DB      - data bus for writing to segment registers (32 bits)
--    CS      - chip select for MMU register writes annd reads fromn OS, active low
--    clock   - the system clock
--
--  Outputs:
--    PAB     - physical address bus (42 bits)
--    DB      - data bus for reading from segment registers (32 bits)
--    SegFault - low if the logical address is not in a valid segment
--    ProtFault - low if the logical address is in a write protected segment and RW is low for write
--    RW_output     - high for read, low for write (passed through from input)
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MMU is
    port (
        RW       : in  std_logic;
        LAB      : in  std_logic_vector(31 downto 0);
        DB       : inout  std_logic_vector(31 downto 0);
        CS       : in  std_logic;
        clock    : in  std_logic;
        PAB      : out std_logic_vector(41 downto 0);
        SegFault : out std_logic;
        ProtFault : out std_logic;
        RW_output : out std_logic
    );
end MMU;

architecture behavior of MMU is
    type  RegType  is array (0 to 3, 0 to 3) of
                      std_logic_vector(31 downto 0); 
    -- 4 sets of segment registers, each with 4 registers 
    -- (starting physical address, starting logical address, logical address mask, index and status)

    signal  Registers : RegType;

    signal  seg_matched : integer range 0 to 3; -- internal signal to track which segment matched for setting U bit on successful match                                                                                                                                                    
    signal  seg_written : integer range 0 to 3; -- internal signal to track which segment was written to for setting D bit on successful write                                                                                                                                                               
    signal  seg_faulted : integer range 0 to 3; -- internal signal to track which segment faulted for setting F bit on protection fault
begin

    -- segment matching, reading, and fault detection
    process(LAB, RW, CS, Registers)
    begin
        SegFault  <= '0';
        ProtFault <= '1';
        PAB       <= (others => '0');
        RW_output <= '1'; -- default to read, will be set to write if successful match and write operation
        if CS = '1' then -- only do matching and output if not being written to

            for i in 0 to 3 loop
                if Registers(i, 3)(27) = '1' and (LAB(31 downto 10) and Registers(i, 2)(31 downto 10)) =
                (Registers(i, 1)(31 downto 10) and Registers(i, 2)(31 downto 10)) then -- check valid bit and match of logical address with segment
                    SegFault <= '1';

                    PAB(9 downto 0) <= LAB(9 downto 0);
                    PAB(41 downto 10) <= Registers(i, 0)
                        or ("0000000000" & (LAB(31 downto 10) and not Registers(i, 2)(31 downto 10)));
                    -- presserve top 1 bits of physical address since we only have these 22 to work with
                    -- and can thus map to greater area 

                    RW_output <= RW; 
                    seg_matched <= i; -- set U bit internal signal on successful match

                    -- check WP bit (bit 29 of status register) on writes
                    if RW = '0' and Registers(i, 3)(29) = '1' then
                        ProtFault <= '0';
                        RW_output <= '1';
                        seg_faulted <= i; -- set F bit internal signal on a protection fault
                    elsif RW = '0' then
                        seg_written <= i; -- set D bit internal signal on successful write
                    end if;
                end if;
            end loop;
        end if;
    end process;

    -- register writes 
    process(clock, CS)
        variable seg : integer range 0 to 3;
    begin
        if rising_edge(clock) then
            DB <= (others => 'Z');
            if (CS = '0') then
                seg := to_integer(unsigned(LAB(3 downto 2)));
                if RW = '0' then
                   case LAB(1 downto 0) is
                    when "00" =>  -- starting physical address 
                        Registers(seg, 0) <= DB;
                    when "01" =>  -- starting logical address 
                        Registers(seg, 1) <= DB;
                    when "10" => -- logical address mask 
                        Registers(seg, 2) <= DB;
                    when "11" =>  -- index and status
                        Registers(seg, 3) <= DB;
                    when others =>
                        null;
                    end case;
                else 
                    case LAB(1 downto 0) is
                    when "00" =>  -- starting physical address
                            DB <= Registers(seg, 0);
                    when "01" =>  -- starting logical address 
                            DB <= Registers(seg, 1);
                    when "10" =>  -- logical address mask 
                            DB <= Registers(seg, 2);
                    when "11" =>  -- index and status
                        DB <= Registers(seg, 3);
                    when others =>
                        null;
                    end case;
                end if;
            else
                -- U bit: set on any successful segment match
                if SegFault = '1' then
                    Registers(seg_matched, 3)(31) <= '1';
                end if;
                -- D bit: set on successful write (no protection fault)
                if SegFault = '1' and RW = '0' and ProtFault = '1' then
                    Registers(seg_written, 3)(30) <= '1';
                end if;
                -- F bit: set on protection fault
                if ProtFault = '0' then
                    Registers(seg_faulted, 3)(28) <= '1';
                end if;
            end if;
        end if;
    end process;

end behavior;