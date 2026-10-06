`timescale 1ns/10ps
// Directed + random unit test for the FPU. Reads vectors produced by
// tools/gen_fp_vectors.py: each line is "op a b expected" in hex.
module fpu_tb;

    logic [1:0]  op;
    logic [31:0] a, b, y;

    fpu dut (.op(op), .a(a), .b(b), .y(y));

    logic [127:0] vec [0:99999];
    integer n, errors;
    string vf;

    initial begin
        if (!$value$plusargs("vec=%s", vf)) vf = "fp_vectors.hex";
        for (int i = 0; i < 100000; i++) vec[i] = '1;
        $readmemh(vf, vec);
        errors = 0;
        n = 0;
        for (int i = 0; i < 100000; i++) begin
            if (n == i && vec[i] !== 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF) begin
                op = vec[i][97:96];
                a  = vec[i][95:64];
                b  = vec[i][63:32];
                #1;
                if (y !== vec[i][31:0]) begin
                    $display("[FAIL] op=%0d a=%08h b=%08h got=%08h exp=%08h",
                             op, a, b, y, vec[i][31:0]);
                    errors++;
                end
                n++;
            end
        end
        if (errors == 0)
            $display("*** FPU PASS *** %0d vectors", n);
        else
            $display("*** FPU FAIL *** %0d/%0d mismatches", errors, n);
        $finish;
    end

endmodule
