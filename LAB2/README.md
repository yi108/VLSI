# LAB2 — VSD HW2: 5-Stage Pipeline RISC-V CPU (RV32IMBF + DSP)

NCKU VLSI System Design 2026 Fall, HW2。實作支援 68 條指令
(RV32I 基本指令 + M + B 子集 + F 子集 + DSP + CSR 計數器)的五級管線 CPU,
IM/DM 介面為 req(單週期脈衝)/valid 握手、隨機延遲。

## 目錄結構(對應繳交規範)

```
LAB2/
├── StudentID            # ← 繳交前改成自己的學號
├── Makefile             # 本機 iverilog 模擬用(課程伺服器請用官方 Makefile)
├── src/                 # RTL(繳交內容)
│   ├── top.sv           # CPU 頂層:管線、hazard/stall/flush、IM/DM FSM
│   ├── decoder.sv       # 指令解碼
│   ├── alu.sv           # 整數 ALU + M + B 子集 + DSP
│   ├── fpu.sv           # FADD.S / FSUB.S / FMIN.S / FMAX.S(RNE 捨入)
│   ├── regfile.sv       # 參數化暫存器檔(整數 x0 硬接 0 / 浮點)
│   ├── imm_ext.sv       # 立即值擴展
│   ├── ld_filter.sv     # Load 資料對齊/延伸
│   └── jb_unit.sv       # 分支/跳躍解析(EX 級)
├── sim/                 # 自製驗證環境(課程伺服器上改用官方 sim/)
│   ├── top_tb.sv        # 自我檢查 testbench,IM/DM 隨機 latency 模型
│   ├── fpu_tb.sv        # FPU 隨機向量單元測試
│   ├── prog0/           # 68 指令全覆蓋測試(asm/hex/data/golden)
│   └── prog1/           # 浮點排序+累加(迴圈/hazard 壓力測試)
├── script/
│   ├── DC.sdc           # clk_period = 2.0(與 top_tb.sv `CYCLE 一致)
│   └── synthesis.tcl    # Design Compiler 合成腳本模板
├── syn/                 # 合成輸出(需在課程伺服器以 DC 產生,見 syn/README.txt)
├── tools/
│   ├── asm.py           # 68 指令組譯器
│   ├── iss.py           # 黃金指令集模擬器(產生 golden_*.hex)
│   └── gen_fp_vectors.py# FPU 測試向量產生器
└── report/report.md     # 報告內容(轉成課程模板 PDF 繳交)
```

## 本機模擬(需 iverilog + python3)

```bash
make rtl0        # prog0:68 指令全覆蓋,與 ISS golden 比對暫存器+記憶體
make rtl1        # prog1:浮點排序/累加
make rtl_all
make fpu         # FPU 3 萬筆隨機向量
make rtl0 SEED=42        # 換隨機 latency 種子
make rtl0 FSDB=1         # 傾印波形 (VCD)
```

## 課程伺服器流程

1. `cp -R /home/soc_course/vsd26/vsd2600/VSD2026_HW2 ./`
2. 將本 repo 的 `src/*.sv` 複製進官方環境的 `src/`
3. `make rtl0` … `make rtl5`、`make synthesize`、`make syn0` … `make syn5`
4. `make check && make tar`,把產生的 `syn/` 檔案與報告一併繳交

## 設計重點

- **IM/DM 握手**:req 單脈衝、未收到 valid 不重發;IF 取指 FSM 在管線 stall 時
  將指令 latch 進 buffer;分支改向時在途請求以 discard 旗標作廢。
- **Hazard**:MEM→EX 與 WB→EX 全旁路(整數/浮點)、regfile write-through、
  load-use 停一拍、branch/jal/jalr 於 EX 解析並 flush 前兩級。
- **FPU**:單週期對齊/相加/正規化/RNE 捨入;結果恰為 0 時輸出 +0;
  FMIN/FMAX 用保序整數鍵比較(-0 < +0)。
- **驗證**:Python 組譯器 + 黃金 ISS 自動比對;IM/DM 隨機 1–4 cycle latency、
  多 seed 迴歸全 PASS;FPU 另以 30,056 筆向量單元測試。
