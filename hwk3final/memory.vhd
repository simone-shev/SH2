----------------------------------------------------------------------------
--
--  Memory Subsystem
--
--  This component describes the memory for a 32-bit byte-addressable CPU
--  with a 32-bit address bus.  Only a portion of the full address space is
--  filled in.  Addresses outside the filled in range return 'X' when read
--  and generate error messages when written.
--
--  Revision History:
--     28 Apr 25  Glen George       Initial revision.
--     29 Apr 25  Glen George       Fixed some syntax errors.
--     29 Apr 25  Glen George       Fixed inconsistencies in byte vs word
--                                  addressing.
--     30 Apr 26  Simone Shevchuk   Parens fixed, RAM_SIZE added
--     01 May 26  Simone Shevchuk   Change write end_if add wait for 0 ns after writing to memory
--     02 May 26  Simone Shevchuk   Add comments
----------------------------------------------------------------------------


--
--  MEMORY32x32
--
--  This is a memory component that supports a byte-addressable 32-bit wide
--  memory with 32-bits of address.  No timing restrictions are implemented,
--  but if the address bus changes while a WE signal is active an error is
--  generated.  Only a portion of the memory is actually usable.  Addresses
--  outside of the four usable ranges return 'X' on read and generate error
--  messages on write.  The size and address of each memory chunk are generic
--  parameters.
--
--  Generics:
--    MEMSIZE     - size of the four memory blocks in 32-bit words
--    START_ADDR0 - starting address of first memory block/chunk
--    START_ADDR1 - starting address of second memory block/chunk
--    START_ADDR2 - starting address of third memory block/chunk
--    START_ADDR3 - starting address of fourth memory block/chunk
--
--  Inputs:
--    RE0    - low byte read enable (active low)
--    RE1    - byte 1 read enable (active low)
--    RE2    - byte 2 read enable (active low)
--    RE3    - high byte read enable (active low)
--    WE0    - low byte write enable (active low)
--    WE1    - byte 1 write enable (active low)
--    WE2    - byte 2 write enable (active low)
--    WE3    - high byte write enable (active low)
--    MemAB  - memory address bus (32 bits)
--
--  Inputs/Outputs:
--    MemDB  - memory data bus (32 bits)
--

library ieee;
use ieee.std_logic_1164.all;
--use ieee.std_logic_arith.all;
--use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;


entity  MEMORY32x32  is

    generic (
        MEMSIZE     : integer := 256;   -- default size is 256 words
        START_ADDR0 : integer;          -- starting address of first block
        START_ADDR1 : integer;          -- starting address of second block
        START_ADDR2 : integer;          -- starting address of third block
        START_ADDR3 : integer           -- starting address of fourth block
    );

    port (
        RE0    : in     std_logic;      -- low byte read enable (active low)
        RE1    : in     std_logic;      -- byte 1 read enable (active low)
        RE2    : in     std_logic;      -- byte 2 read enable (active low)
        RE3    : in     std_logic;      -- high byte read enable (active low)
        WE0    : in     std_logic;      -- low byte write enable (active low)
        WE1    : in     std_logic;      -- byte 1 write enable (active low)
        WE2    : in     std_logic;      -- byte 2 write enable (active low)
        WE3    : in     std_logic;      -- high byte write enable (active low)
        MemAB  : in     std_logic_vector(31 downto 0);  -- memory address bus
        MemDB  : inout  std_logic_vector(31 downto 0)   -- memory data bus
    );

end  MEMORY32x32;


architecture  behavioral  of  MEMORY32x32  is
    constant RAM_SIZE : integer := MEMSIZE; -- size of each memory block in bytes

    -- define the type for the RAM chunks
    type  RAMtype  is array (0 to MEMSIZE - 1) of std_logic_vector(31 downto 0);

    -- now define the RAMs (initialized to X)
    signal  RAMbits0  :  RAMtype  := (others => (others => 'X'));
    signal  RAMbits1  :  RAMtype  := (others => (others => 'X'));
    signal  RAMbits2  :  RAMtype  := (others => (others => 'X'));
    signal  RAMbits3  :  RAMtype  := (others => (others => 'X'));

    -- general read and write signals
    signal  RE  :  std_logic;
    signal  WE  :  std_logic;

    -- data read from memory
    signal  MemData  :  std_logic_vector(31 downto 0);


begin


    -- compute the general read and write signals (active low signals)
    RE  <=  RE0  and  RE1  and  RE2  and  RE3;
    WE  <=  WE0  and  WE1  and  WE2  and  WE3;


    process
        -- variable wr_data : std_logic_vector(31 downto 0);
    begin

        -- wait for an input to change
        wait on  RE, RE0, RE1, RE2, RE3, WE, WE0, WE1, WE2, WE3, MemAB;

        -- first check if reading
        if  (RE = '0')  then
            -- reading, put the data out (check the address)
            if  ((to_integer(unsigned(MemAB)) >= START_ADDR0) and
                 (to_integer(unsigned(MemAB)) - START_ADDR0 < (4 * RAM_SIZE)))  then
                MemDB <= RAMbits0(to_integer(unsigned(MemAB(31 downto 2))) - START_ADDR0 / 4);
            elsif  ((to_integer(unsigned(MemAB)) >= START_ADDR1) and
                    (to_integer(unsigned(MemAB)) - START_ADDR1 < (4 * RAM_SIZE)))  then
                MemDB <= RAMbits1(to_integer(unsigned(MemAB(31 downto 2))) - START_ADDR1 / 4);
            elsif  ((to_integer(unsigned(MemAB)) >= START_ADDR2) and
                 (to_integer(unsigned(MemAB)) - START_ADDR2 < (4 * RAM_SIZE)))  then
                MemDB <= RAMbits2(to_integer(unsigned(MemAB(31 downto 2))) - START_ADDR2 / 4);
            elsif  ((to_integer(unsigned(MemAB)) >= START_ADDR3) and
                 (to_integer(unsigned(MemAB)) - START_ADDR3 < (4 * RAM_SIZE)))  then
                MemDB <= RAMbits3(to_integer(unsigned(MemAB(31 downto 2))) - START_ADDR3 / 4);
            else
                -- outside of any allowable address range - set output to X
                MemDB <= (others => 'X');
            end if;

            -- only set the bytes that are being read
            if  RE0 /= '0'  then
                MemDB(7 downto 0) <= (others => 'Z');
            end if;
            if  RE1 /= '0'  then
                MemDB(15 downto 8) <= (others => 'Z');
            end if;
            if  RE2 /= '0'  then
                MemDB(23 downto 16) <= (others => 'Z');
            end if;
            if  RE3 /= '0'  then
                MemDB(31 downto 24) <= (others => 'Z');
            end if;

        else

            -- not reading, send data bus to hi-Z
            MemDB <= (others => 'Z');
        end if;

        -- now check if writing (falling edge: data and WE0-3 are valid)
        if  (WE'event and (WE = '0'))  then
            -- read current value at the target address
            if  ((to_integer(unsigned(MemAB)) >= START_ADDR0) and
                 (to_integer(unsigned(MemAB)) - START_ADDR0 < (4 * RAM_SIZE)))  then
                MemData <= RAMbits0(to_integer(unsigned(MemAB(31 downto 2))) - START_ADDR0 / 4);
            elsif  ((to_integer(unsigned(MemAB)) >= START_ADDR1) and
                    (to_integer(unsigned(MemAB)) - START_ADDR1 < (4 * RAM_SIZE)))  then
                MemData <= RAMbits1(to_integer(unsigned(MemAB(31 downto 2))) - START_ADDR1 / 4);
            elsif  ((to_integer(unsigned(MemAB)) >= START_ADDR2) and
                    (to_integer(unsigned(MemAB)) - START_ADDR2 < (4 * RAM_SIZE)))  then
                --wr_data := RAMbits2(to_integer(unsigned(MemAB(31 downto 2))) - START_ADDR2 / 4);
                MemData <= RAMbits2(to_integer(unsigned(MemAB(31 downto 2))) - START_ADDR2 / 4);
            elsif  ((to_integer(unsigned(MemAB)) >= START_ADDR3) and
                    (to_integer(unsigned(MemAB)) - START_ADDR3 < (4 * RAM_SIZE)))  then
                MemData <= RAMbits3(to_integer(unsigned(MemAB(31 downto 2))) - START_ADDR3 / 4);
            else
                MemData <= (others => 'X');
            end if;
            wait for 0 ns; -- wait for data to be read

            -- merge bytes being written (WE0-3 are still '0' on falling edge)
            if  WE0 = '0'  then
                -- wr_data(7 downto 0) := MemDB(7 downto 0);
                MemData(7 downto 0) <= MemDB(7 downto 0);
            end if;
            if  WE1 = '0'  then
                MemData(15 downto 8) <= MemDB(15 downto 8);
            end if;
            if  WE2 = '0'  then
                MemData(23 downto 16) <= MemDB(23 downto 16);
            end if;
            if  WE3 = '0'  then
                MemData(31 downto 24) <= MemDB(31 downto 24);
            end if;
            wait for 0 ns; -- wait for data to be merged

            -- write merged value back to memory
            if  ((to_integer(unsigned(MemAB)) >= START_ADDR0) and
                 (to_integer(unsigned(MemAB)) - START_ADDR0 < (4 * RAM_SIZE)))  then
                RAMbits0(to_integer(unsigned(MemAB(31 downto 2))) - START_ADDR0 / 4) <= MemData;
            elsif  ((to_integer(unsigned(MemAB)) >= START_ADDR1) and
                    (to_integer(unsigned(MemAB)) - START_ADDR1 < (4 * RAM_SIZE)))  then
                RAMbits1(to_integer(unsigned(MemAB(31 downto 2))) - START_ADDR1 / 4) <= MemData;
            elsif  ((to_integer(unsigned(MemAB)) >= START_ADDR2) and
                    (to_integer(unsigned(MemAB)) - START_ADDR2 < (4 * RAM_SIZE)))  then
                RAMbits2(to_integer(unsigned(MemAB(31 downto 2))) - START_ADDR2 / 4) <= MemData;
            elsif  ((to_integer(unsigned(MemAB)) >= START_ADDR3) and
                    (to_integer(unsigned(MemAB)) - START_ADDR3 < (4 * RAM_SIZE)))  then
                RAMbits3(to_integer(unsigned(MemAB(31 downto 2))) - START_ADDR3 / 4) <= MemData;
            else
                assert (false)
                    report  "Attempt to write to a non-existant address"
                    severity  ERROR;
            end if;

            -- wait for the update to happen
            wait for 0 ns;

        -- finally check if WE low with the address changing
        if  (MemAB'event and (WE = '0'))  then
            REPORT "Glitch on Memory Address bus"
            SEVERITY  ERROR;
            end if;
        end if;

    end process;


end  behavioral;
