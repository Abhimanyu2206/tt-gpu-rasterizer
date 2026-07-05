import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

@cocotb.test()
async def test_project(dut):
    dut._log.info("Starting Streaming Rasterizer Silicon Test Engine...")

    # --- Start System Clock (100MHz equivalent simulation steps) ---
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # --- Hardware Reset Phase ---
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # --- Loading Counter-Clockwise (CCW) Triangle Mesh Data ---
    # Vertex V0 (X=7, Y=2) -> Binary: 1 010 0111 -> 0xA7
    dut._log.info("Streaming Geometric Point V0 (7,2)")
    dut.ui_in.value = 0xA7
    await RisingEdge(dut.clk)
    dut.ui_in.value = 0x00
    await ClockCycles(dut.clk, 2)

    # Vertex V1 (X=2, Y=1) -> Binary: 1 001 0010 -> 0x92
    dut._log.info("Streaming Geometric Point V1 (2,1)")
    dut.ui_in.value = 0x92
    await RisingEdge(dut.clk)
    dut.ui_in.value = 0x00
    await ClockCycles(dut.clk, 2)

    # Vertex V2 (X=4, Y=6) with Checkerboard Mode (01) -> Binary: 1 011 0100 -> 0xB4
    dut._log.info("Streaming Geometric Point V2 (4,6) [Shader: Checkerboard]")
    dut.ui_in.value = 0xB4
    await RisingEdge(dut.clk)
    dut.ui_in.value = 0x00
    await RisingEdge(dut.clk)

    # --- Hardware Pipeline Process Tracking Loop ---
    dut._log.info("Waiting for core to enter STATE_RENDER phase...")
    
    # Run the clock and watch the outputs step forward
    for cycle in range(60):
        await RisingEdge(dut.clk)
        out_val = int(dut.uo_out.value)
        
        # Check if rendering valid bit is high (uo_out[7])
        if (out_val & 0x80):
            color_bits = (out_val & 0x3F)
            dut._log.info(f"Cycle {cycle}: Processing Screen Pixel Box. Color bits out (HEX) = {hex(color_bits)}")
        
        # Check if FSM tripped the finished bit (uo_out[6])
        if (out_val & 0x40):
            dut._log.info("Core triggered Hardware DONE Interrupt Flag successfully!")
            break

    assert (int(dut.uo_out.value) & 0x40) != 0, "Error: Rasterization process failed to complete safely!"
    dut._log.info("All Hardware Sanity Checks Passed. Design is rock solid!")
