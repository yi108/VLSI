`timescale 1ns/10ps
`define CYCLE 2.0
`define MAX_CYCLE 500000

// Self-checking testbench for the VSD HW2 CPU.
//  +prog=<file>    instruction memory image (hex, one word per line)
//  +data=<file>    initial data memory image (optional)
//  +gold_x=<file>  golden integer register file
//  +gold_f=<file>  golden float register file
//  +gold_d=<file>  golden data memory
// IM and DM reply with random 1..4 cycle latency over the req/valid protocol.
module top_tb;

    localparam IM_WORDS = 16384;
    localparam DM_WORDS = 16384;

    logic clk, rst;

    logic        im_req,  im_valid;
    logic [31:0] im_addr, im_read_data;
    logic        dm_req,  dm_WEB, dm_valid;
    logic [31:0] dm_bit_en, dm_addr, dm_write_data, dm_read_data;

    top dut (
        .clk           (clk),
        .rst           (rst),
        .im_req        (im_req),
        .im_addr       (im_addr),
        .im_read_data  (im_read_data),
        .im_valid      (im_valid),
        .dm_req        (dm_req),
        .dm_WEB        (dm_WEB),
        .dm_bit_en     (dm_bit_en),
        .dm_addr       (dm_addr),
        .dm_write_data (dm_write_data),
        .dm_read_data  (dm_read_data),
        .dm_valid      (dm_valid)
    );

    always #(`CYCLE / 2.0) clk = ~clk;

    // ------------------------------------------------------------------
    // memories
    // ------------------------------------------------------------------
    logic [31:0] im [0:IM_WORDS-1];
    logic [31:0] dm [0:DM_WORDS-1];

    // instruction memory model
    integer im_lat;
    logic [31:0] im_pend_addr;
    logic        im_busy;
    always @(posedge clk) begin
        if (rst) begin
            im_valid <= 1'b0;
            im_busy  <= 1'b0;
            im_lat   <= 0;
        end else begin
            im_valid <= 1'b0;
            if (im_req && !im_busy) begin
                im_busy      <= 1'b1;
                im_pend_addr <= im_addr;
                im_lat       <= (($random(seed)>>2) & 3) + 1;
            end else if (im_busy) begin
                if (im_lat > 1) begin
                    im_lat <= im_lat - 1;
                end else begin
                    im_valid     <= 1'b1;
                    im_read_data <= im[im_pend_addr[31:2] % IM_WORDS];
                    im_busy      <= 1'b0;
                end
            end
        end
    end

    // data memory model
    integer dm_lat;
    logic [31:0] dm_pend_addr, dm_pend_wdata, dm_pend_biten;
    logic        dm_pend_web, dm_busy;
    always @(posedge clk) begin
        if (rst) begin
            dm_valid <= 1'b0;
            dm_busy  <= 1'b0;
            dm_lat   <= 0;
        end else begin
            dm_valid <= 1'b0;
            if (dm_req && !dm_busy) begin
                dm_busy       <= 1'b1;
                dm_pend_addr  <= dm_addr;
                dm_pend_wdata <= dm_write_data;
                dm_pend_biten <= dm_bit_en;
                dm_pend_web   <= dm_WEB;
                dm_lat        <= (($random(seed)>>2) & 3) + 1;
            end else if (dm_busy) begin
                if (dm_lat > 1) begin
                    dm_lat <= dm_lat - 1;
                end else begin
                    dm_valid <= 1'b1;
                    if (dm_pend_web) begin
                        dm_read_data <= dm[dm_pend_addr[31:2] % DM_WORDS];
                    end else begin
                        dm[dm_pend_addr[31:2] % DM_WORDS] <=
                            (dm[dm_pend_addr[31:2] % DM_WORDS] & dm_pend_biten) |
                            (dm_pend_wdata & ~dm_pend_biten);
                    end
                    dm_busy <= 1'b0;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // run control: detect the `jal x0, 0` self-loop as program halt
    // ------------------------------------------------------------------
    integer halt_seen;
    integer cycle_cnt;
    always @(posedge clk) begin
        if (rst) begin
            halt_seen <= 0;
            cycle_cnt <= 0;
        end else begin
            cycle_cnt <= cycle_cnt + 1;
            if (im_valid && im_read_data == 32'h0000006F)
                halt_seen <= halt_seen + 1;
        end
    end

    // ------------------------------------------------------------------
    // init / golden compare
    // ------------------------------------------------------------------
    logic [31:0] gold_x [0:31];
    logic [31:0] gold_f [0:31];
    logic [31:0] gold_d [0:DM_WORDS-1];
    string prog_f, data_f, goldx_f, goldf_f, goldd_f;
    integer errors;
    integer seed, dummy;

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        im_valid = 1'b0;
        dm_valid = 1'b0;
        errors = 0;

        for (int i = 0; i < IM_WORDS; i++) im[i] = 32'h0000_0013;  // nop
        for (int i = 0; i < DM_WORDS; i++) begin
            dm[i]     = 32'd0;
            gold_d[i] = 32'd0;
        end
        for (int i = 0; i < 32; i++) begin
            gold_x[i] = 32'd0;
            gold_f[i] = 32'd0;
        end

        if (!$value$plusargs("prog=%s", prog_f)) prog_f = "prog.hex";
        if ($value$plusargs("data=%s", data_f))  $readmemh(data_f, dm);
        $readmemh(prog_f, im);
        if ($value$plusargs("gold_x=%s", goldx_f)) $readmemh(goldx_f, gold_x);
        if ($value$plusargs("gold_f=%s", goldf_f)) $readmemh(goldf_f, gold_f);
        if ($value$plusargs("gold_d=%s", goldd_f)) $readmemh(goldd_f, gold_d);

        `ifdef FSDB
            $dumpfile("top_tb.vcd");
            $dumpvars(0, top_tb);
        `endif

        repeat (5) @(negedge clk);
        rst = 1'b0;

        // wait for halt loop, then drain the pipeline
        wait (halt_seen >= 3);
        repeat (40) @(negedge clk);

        // compare integer registers (skip x0)
        for (int i = 1; i < 32; i++) begin
            if (dut.u_rf.mem[i] !== gold_x[i]) begin
                $display("[FAIL] x%0d = %08h, expected %08h", i, dut.u_rf.mem[i], gold_x[i]);
                errors++;
            end
        end
        // compare float registers
        for (int i = 0; i < 32; i++) begin
            if (dut.u_frf.mem[i] !== gold_f[i]) begin
                $display("[FAIL] f%0d = %08h, expected %08h", i, dut.u_frf.mem[i], gold_f[i]);
                errors++;
            end
        end
        // compare data memory
        for (int i = 0; i < DM_WORDS; i++) begin
            if (dm[i] !== gold_d[i]) begin
                $display("[FAIL] dm[%08h] = %08h, expected %08h", i*4, dm[i], gold_d[i]);
                errors++;
            end
        end

        if (errors == 0)
            $display("*** PASS *** (%0d cycles)", cycle_cnt);
        else
            $display("*** FAIL *** %0d mismatches (%0d cycles)", errors, cycle_cnt);
        $finish;
    end

    initial begin
        repeat (`MAX_CYCLE) @(posedge clk);
        $display("*** TIMEOUT *** simulation exceeded %0d cycles", `MAX_CYCLE);
        $finish;
    end

endmodule
