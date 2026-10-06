// VSD HW2 - 5-stage pipelined RISC-V CPU (RV32I + M + B-subset + F-subset + DSP).
//
// Pipeline: IF -> ID -> EX -> MEM -> WB
//  * IM/DM use a req(1-cycle pulse)/valid handshake with random latency; the
//    IF stage fetches through a small FSM and the MEM stage stalls the pipe
//    until dm_valid.
//  * ALU->ALU hazards are resolved by forwarding (MEM->EX and WB->EX),
//    load-use hazards by a one-bubble stall, control hazards by resolving
//    jumps/branches in EX and flushing IF/ID + ID/EX.
module top (
    input  logic        clk,
    input  logic        rst,

    // instruction memory interface
    output logic        im_req,
    output logic [31:0] im_addr,
    input  logic [31:0] im_read_data,
    input  logic        im_valid,

    // data memory interface
    output logic        dm_req,
    output logic        dm_WEB,      // 0: write, 1: read
    output logic [31:0] dm_bit_en,   // active-low byte-wise bit mask
    output logic [31:0] dm_addr,
    output logic [31:0] dm_write_data,
    input  logic [31:0] dm_read_data,
    input  logic        dm_valid
);

    // ------------------------------------------------------------------
    // forward declarations of pipeline/stall control
    // ------------------------------------------------------------------
    logic mem_busy;      // MEM stage waiting on DM handshake
    logic load_use;      // load-use hazard between EX and ID
    logic branch_taken;  // resolved in EX, redirects the PC
    logic [31:0] jb_target;

    // ==================================================================
    // IF stage: PC + fetch FSM (req pulse, wait for valid, hold buffer)
    // ==================================================================
    localparam logic [1:0] F_REQ = 2'd0, F_WAIT = 2'd1, F_HOLD = 2'd2;

    logic [1:0]  fstate;
    logic [31:0] pc_r;
    logic [31:0] if_buf;
    logic        discard_r;  // in-flight fetch belongs to a flushed path

    logic        if_ready;
    logic [31:0] if_inst;
    logic        if_accept;

    assign if_ready  = (fstate == F_WAIT && im_valid && !discard_r) || (fstate == F_HOLD);
    assign if_inst   = (fstate == F_HOLD) ? if_buf : im_read_data;
    assign if_accept = if_ready && !mem_busy && !branch_taken && !load_use;

    assign im_req  = (fstate == F_REQ) && !rst;
    assign im_addr = pc_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            fstate    <= F_REQ;
            pc_r      <= 32'd0;
            discard_r <= 1'b0;
            if_buf    <= 32'd0;
        end else begin
            unique case (fstate)
                F_REQ:  fstate <= F_WAIT;
                F_WAIT: if (im_valid) begin
                    if (discard_r) begin
                        discard_r <= 1'b0;
                        fstate    <= F_REQ;
                    end else if (if_accept) begin
                        pc_r   <= pc_r + 32'd4;
                        fstate <= F_REQ;
                    end else begin
                        if_buf <= im_read_data;
                        fstate <= F_HOLD;
                    end
                end
                default: /* F_HOLD */ if (if_accept) begin
                    pc_r   <= pc_r + 32'd4;
                    fstate <= F_REQ;
                end
            endcase

            if (branch_taken) begin  // overrides the transitions above
                pc_r <= jb_target;
                unique case (fstate)
                    F_REQ:  begin fstate <= F_WAIT; discard_r <= 1'b1; end
                    F_WAIT: begin
                        if (im_valid) begin fstate <= F_REQ; discard_r <= 1'b0; end
                        else discard_r <= 1'b1;
                    end
                    default: fstate <= F_REQ;  // F_HOLD: drop buffered inst
                endcase
            end
        end
    end

    // ==================================================================
    // IF/ID pipeline register
    // ==================================================================
    logic        ifid_valid;
    logic [31:0] ifid_inst, ifid_pc;

    always_ff @(posedge clk) begin
        if (rst) begin
            ifid_valid <= 1'b0;
            ifid_inst  <= 32'd0;
            ifid_pc    <= 32'd0;
        end else if (!mem_busy) begin
            if (branch_taken) begin
                ifid_valid <= 1'b0;
            end else if (load_use) begin
                // hold
            end else if (if_ready) begin
                ifid_valid <= 1'b1;
                ifid_inst  <= if_inst;
                ifid_pc    <= pc_r;
            end else begin
                ifid_valid <= 1'b0;
            end
        end
    end

    // ==================================================================
    // ID stage: decode, immediate, register file read
    // ==================================================================
    logic [4:0]  d_rs1, d_rs2, d_rd;
    logic        d_uses_rs1, d_uses_rs2, d_uses_frs1, d_uses_frs2;
    logic        d_rf_we, d_frf_we;
    logic [4:0]  d_alu_op;
    logic [1:0]  d_opa_sel;
    logic        d_opb_sel;
    logic [2:0]  d_imm_type;
    logic        d_is_load, d_is_store, d_store_fp;
    logic [2:0]  d_mem_f3;
    logic        d_is_branch, d_is_jal, d_is_jalr;
    logic        d_is_fpu;
    logic [1:0]  d_fpu_op;
    logic        d_is_csr;
    logic [11:0] d_csr_addr;
    logic        d_wb_mem;

    decoder u_decoder (
        .inst      (ifid_inst),
        .rs1       (d_rs1),
        .rs2       (d_rs2),
        .rd        (d_rd),
        .uses_rs1  (d_uses_rs1),
        .uses_rs2  (d_uses_rs2),
        .uses_frs1 (d_uses_frs1),
        .uses_frs2 (d_uses_frs2),
        .rf_we     (d_rf_we),
        .frf_we    (d_frf_we),
        .alu_op    (d_alu_op),
        .opa_sel   (d_opa_sel),
        .opb_sel   (d_opb_sel),
        .imm_type  (d_imm_type),
        .is_load   (d_is_load),
        .is_store  (d_is_store),
        .store_fp  (d_store_fp),
        .mem_f3    (d_mem_f3),
        .is_branch (d_is_branch),
        .is_jal    (d_is_jal),
        .is_jalr   (d_is_jalr),
        .is_fpu    (d_is_fpu),
        .fpu_op    (d_fpu_op),
        .is_csr    (d_is_csr),
        .csr_addr  (d_csr_addr),
        .wb_mem    (d_wb_mem)
    );

    logic [31:0] d_imm;
    imm_ext u_imm_ext (
        .inst     (ifid_inst),
        .imm_type (d_imm_type),
        .imm      (d_imm)
    );

    // writeback signals (declared here, driven in WB)
    logic        wb_rf_we, wb_frf_we;
    logic [4:0]  wb_rd;
    logic [31:0] wb_data;

    logic [31:0] rf_rdata1, rf_rdata2, frf_rdata1, frf_rdata2;

    regfile #(.HARD_ZERO(1)) u_rf (
        .clk    (clk),
        .rst    (rst),
        .raddr1 (d_rs1),
        .raddr2 (d_rs2),
        .rdata1 (rf_rdata1),
        .rdata2 (rf_rdata2),
        .we     (wb_rf_we),
        .waddr  (wb_rd),
        .wdata  (wb_data)
    );

    regfile #(.HARD_ZERO(0)) u_frf (
        .clk    (clk),
        .rst    (rst),
        .raddr1 (d_rs1),
        .raddr2 (d_rs2),
        .rdata1 (frf_rdata1),
        .rdata2 (frf_rdata2),
        .we     (wb_frf_we),
        .waddr  (wb_rd),
        .wdata  (wb_data)
    );

    // ==================================================================
    // ID/EX pipeline register
    // ==================================================================
    logic        idex_valid;
    logic [31:0] idex_pc, idex_imm;
    logic [31:0] idex_rs1_data, idex_rs2_data;
    logic [4:0]  idex_rs1, idex_rs2, idex_rd;
    logic        idex_uses_frs1, idex_uses_frs2;
    logic        idex_rf_we, idex_frf_we;
    logic [4:0]  idex_alu_op;
    logic [1:0]  idex_opa_sel;
    logic        idex_opb_sel;
    logic        idex_is_load, idex_is_store, idex_store_fp;
    logic [2:0]  idex_mem_f3;
    logic        idex_is_branch, idex_is_jal, idex_is_jalr;
    logic        idex_is_fpu;
    logic [1:0]  idex_fpu_op;
    logic        idex_is_csr;
    logic [11:0] idex_csr_addr;
    logic        idex_wb_mem;

    wire idex_bubble = !ifid_valid || load_use || branch_taken;

    always_ff @(posedge clk) begin
        if (rst) begin
            idex_valid     <= 1'b0;
            idex_rf_we     <= 1'b0;
            idex_frf_we    <= 1'b0;
            idex_is_load   <= 1'b0;
            idex_is_store  <= 1'b0;
            idex_is_branch <= 1'b0;
            idex_is_jal    <= 1'b0;
            idex_is_jalr   <= 1'b0;
        end else if (!mem_busy) begin
            if (idex_bubble) begin
                idex_valid     <= 1'b0;
                idex_rf_we     <= 1'b0;
                idex_frf_we    <= 1'b0;
                idex_is_load   <= 1'b0;
                idex_is_store  <= 1'b0;
                idex_is_branch <= 1'b0;
                idex_is_jal    <= 1'b0;
                idex_is_jalr   <= 1'b0;
            end else begin
                idex_valid     <= 1'b1;
                idex_pc        <= ifid_pc;
                idex_imm       <= d_imm;
                idex_rs1_data  <= d_uses_frs1 ? frf_rdata1 : rf_rdata1;
                idex_rs2_data  <= d_uses_frs2 ? frf_rdata2 : rf_rdata2;
                idex_rs1       <= d_rs1;
                idex_rs2       <= d_rs2;
                idex_rd        <= d_rd;
                idex_uses_frs1 <= d_uses_frs1;
                idex_uses_frs2 <= d_uses_frs2;
                idex_rf_we     <= d_rf_we;
                idex_frf_we    <= d_frf_we;
                idex_alu_op    <= d_alu_op;
                idex_opa_sel   <= d_opa_sel;
                idex_opb_sel   <= d_opb_sel;
                idex_is_load   <= d_is_load;
                idex_is_store  <= d_is_store;
                idex_store_fp  <= d_store_fp;
                idex_mem_f3    <= d_mem_f3;
                idex_is_branch <= d_is_branch;
                idex_is_jal    <= d_is_jal;
                idex_is_jalr   <= d_is_jalr;
                idex_is_fpu    <= d_is_fpu;
                idex_fpu_op    <= d_fpu_op;
                idex_is_csr    <= d_is_csr;
                idex_csr_addr  <= d_csr_addr;
                idex_wb_mem    <= d_wb_mem;
            end
        end
    end

    // load-use hazard: instruction in EX is a load whose rd is a source of
    // the instruction currently in ID
    always_comb begin
        load_use = 1'b0;
        if (idex_valid && idex_is_load && ifid_valid) begin
            if (idex_rf_we) begin  // integer load
                if ((d_uses_rs1 && d_rs1 == idex_rd && d_rs1 != 5'd0) ||
                    (d_uses_rs2 && d_rs2 == idex_rd && d_rs2 != 5'd0))
                    load_use = 1'b1;
            end
            if (idex_frf_we) begin  // FLW
                if ((d_uses_frs1 && d_rs1 == idex_rd) ||
                    (d_uses_frs2 && d_rs2 == idex_rd))
                    load_use = 1'b1;
            end
        end
    end

    // ==================================================================
    // EX stage: forwarding, ALU/FPU/CSR, jump-branch resolution
    // ==================================================================
    // EX/MEM pipeline register (declared early for forwarding)
    logic        exmem_valid;
    logic [31:0] exmem_result, exmem_store_data;
    logic [4:0]  exmem_rd;
    logic        exmem_rf_we, exmem_frf_we;
    logic        exmem_is_load, exmem_is_store, exmem_store_fp;
    logic [2:0]  exmem_mem_f3;
    logic        exmem_wb_mem;

    // MEM/WB pipeline register
    logic        memwb_valid;
    logic [31:0] memwb_data;
    logic [4:0]  memwb_rd;
    logic        memwb_rf_we, memwb_frf_we;

    // load data currently being returned by the DM (MEM stage)
    logic [31:0] mem_ld_data;
    // value available for forwarding from the MEM stage
    wire [31:0] exmem_fwd = exmem_wb_mem ? mem_ld_data : exmem_result;

    logic [31:0] fw_rs1, fw_rs2;

    always_comb begin
        // rs1 operand
        if (idex_uses_frs1) begin
            if      (exmem_valid && exmem_frf_we && exmem_rd == idex_rs1) fw_rs1 = exmem_fwd;
            else if (memwb_valid && memwb_frf_we && memwb_rd == idex_rs1) fw_rs1 = memwb_data;
            else                                                          fw_rs1 = idex_rs1_data;
        end else begin
            if      (exmem_valid && exmem_rf_we && exmem_rd == idex_rs1 && idex_rs1 != 5'd0) fw_rs1 = exmem_fwd;
            else if (memwb_valid && memwb_rf_we && memwb_rd == idex_rs1 && idex_rs1 != 5'd0) fw_rs1 = memwb_data;
            else                                                                             fw_rs1 = idex_rs1_data;
        end
        // rs2 operand (also the store data)
        if (idex_uses_frs2) begin
            if      (exmem_valid && exmem_frf_we && exmem_rd == idex_rs2) fw_rs2 = exmem_fwd;
            else if (memwb_valid && memwb_frf_we && memwb_rd == idex_rs2) fw_rs2 = memwb_data;
            else                                                          fw_rs2 = idex_rs2_data;
        end else begin
            if      (exmem_valid && exmem_rf_we && exmem_rd == idex_rs2 && idex_rs2 != 5'd0) fw_rs2 = exmem_fwd;
            else if (memwb_valid && memwb_rf_we && memwb_rd == idex_rs2 && idex_rs2 != 5'd0) fw_rs2 = memwb_data;
            else                                                                             fw_rs2 = idex_rs2_data;
        end
    end

    // ALU
    logic [31:0] alu_a, alu_b, alu_y;
    always_comb begin
        unique case (idex_opa_sel)
            2'd1:    alu_a = idex_pc;
            2'd2:    alu_a = 32'd0;
            default: alu_a = fw_rs1;
        endcase
        alu_b = idex_opb_sel ? idex_imm : fw_rs2;
    end

    alu u_alu (
        .op (idex_alu_op),
        .a  (alu_a),
        .b  (alu_b),
        .y  (alu_y)
    );

    // FPU
    logic [31:0] fpu_y;
    fpu u_fpu (
        .op (idex_fpu_op),
        .a  (fw_rs1),
        .b  (fw_rs2),
        .y  (fpu_y)
    );

    // CSR performance counters
    logic [63:0] csr_cycle, csr_instret;
    logic [31:0] csr_val;
    always_ff @(posedge clk) begin
        if (rst) begin
            csr_cycle   <= 64'd0;
            csr_instret <= 64'd0;
        end else begin
            csr_cycle <= csr_cycle + 64'd1;
            if (!mem_busy && exmem_valid)  // instruction retires into WB
                csr_instret <= csr_instret + 64'd1;
        end
    end

    always_comb begin
        unique case (idex_csr_addr)
            12'hC00: csr_val = csr_cycle[31:0];
            12'hC80: csr_val = csr_cycle[63:32];
            12'hC02: csr_val = csr_instret[31:0];
            12'hC82: csr_val = csr_instret[63:32];
            default: csr_val = 32'd0;
        endcase
    end

    // jump / branch
    logic jb_taken;
    jb_unit u_jb (
        .is_branch (idex_is_branch),
        .is_jal    (idex_is_jal),
        .is_jalr   (idex_is_jalr),
        .funct3    (idex_mem_f3),
        .rs1_data  (fw_rs1),
        .rs2_data  (fw_rs2),
        .pc        (idex_pc),
        .imm       (idex_imm),
        .taken     (jb_taken),
        .target    (jb_target)
    );

    assign branch_taken = idex_valid && jb_taken && !mem_busy;

    // EX result mux
    logic [31:0] ex_result;
    always_comb begin
        if (idex_is_fpu)                     ex_result = fpu_y;
        else if (idex_is_csr)                ex_result = csr_val;
        else if (idex_is_jal || idex_is_jalr) ex_result = idex_pc + 32'd4;
        else                                 ex_result = alu_y;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            exmem_valid    <= 1'b0;
            exmem_rf_we    <= 1'b0;
            exmem_frf_we   <= 1'b0;
            exmem_is_load  <= 1'b0;
            exmem_is_store <= 1'b0;
        end else if (!mem_busy) begin
            exmem_valid      <= idex_valid;
            exmem_result     <= ex_result;
            exmem_store_data <= fw_rs2;
            exmem_rd         <= idex_rd;
            exmem_rf_we      <= idex_valid && idex_rf_we;
            exmem_frf_we     <= idex_valid && idex_frf_we;
            exmem_is_load    <= idex_valid && idex_is_load;
            exmem_is_store   <= idex_valid && idex_is_store;
            exmem_store_fp   <= idex_store_fp;
            exmem_mem_f3     <= idex_mem_f3;
            exmem_wb_mem     <= idex_valid && idex_wb_mem;
        end
    end

    // ==================================================================
    // MEM stage: DM handshake FSM + load filter
    // ==================================================================
    localparam logic M_IDLE = 1'b0, M_WAIT = 1'b1;
    logic mstate;

    wire mem_op = exmem_valid && (exmem_is_load || exmem_is_store);

    assign dm_req   = mem_op && (mstate == M_IDLE) && !rst;
    assign mem_busy = mem_op && !(mstate == M_WAIT && dm_valid);

    always_ff @(posedge clk) begin
        if (rst) begin
            mstate <= M_IDLE;
        end else begin
            if (dm_req)                        mstate <= M_WAIT;
            else if (mstate == M_WAIT && dm_valid) mstate <= M_IDLE;
        end
    end

    // request signals (sampled by the memory in the dm_req cycle)
    logic [1:0] mem_off;
    always_comb begin
        mem_off       = exmem_result[1:0];
        dm_addr       = {exmem_result[31:2], 2'b00};
        dm_WEB        = ~exmem_is_store;  // 0: write, 1: read
        dm_write_data = exmem_store_data << {mem_off, 3'b000};
        if (exmem_is_store) begin
            unique case (exmem_mem_f3)
                3'b000:  dm_bit_en = ~(32'h0000_00FF << {mem_off, 3'b000});       // SB
                3'b001:  dm_bit_en = ~(32'h0000_FFFF << {mem_off[1], 4'b0000});   // SH
                default: dm_bit_en = 32'h0000_0000;                               // SW / FSW
            endcase
        end else begin
            dm_bit_en = 32'h0000_0000;  // read whole word
        end
    end

    ld_filter u_ld_filter (
        .rdata  (dm_read_data),
        .offset (mem_off),
        .funct3 (exmem_mem_f3),
        .ldata  (mem_ld_data)
    );

    // ==================================================================
    // MEM/WB pipeline register + WB stage
    // ==================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            memwb_valid  <= 1'b0;
            memwb_rf_we  <= 1'b0;
            memwb_frf_we <= 1'b0;
        end else if (mem_busy) begin
            memwb_valid  <= 1'b0;  // bubble while MEM waits
            memwb_rf_we  <= 1'b0;
            memwb_frf_we <= 1'b0;
        end else begin
            memwb_valid  <= exmem_valid;
            memwb_rf_we  <= exmem_valid && exmem_rf_we;
            memwb_frf_we <= exmem_valid && exmem_frf_we;
            memwb_rd     <= exmem_rd;
            memwb_data   <= exmem_wb_mem ? mem_ld_data : exmem_result;
        end
    end

    assign wb_rf_we  = memwb_valid && memwb_rf_we;
    assign wb_frf_we = memwb_valid && memwb_frf_we;
    assign wb_rd     = memwb_rd;
    assign wb_data   = memwb_data;

endmodule
