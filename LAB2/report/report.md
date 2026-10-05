# VSD HW2 Report — 5-Stage Pipeline CPU Design

> 轉成課程報告模板 / PDF(E2XXXXXXX_HW2.pdf)後上傳 Moodle。
> Table 1 的合成數據(面積、slack、模擬時間)需在課程伺服器跑完 `make syn_all` 後補上。

## Table 1 — Summary

| Item | Value |
|---|---|
| ISA | RV32I + M + B-subset + F-subset + DSP(68 條指令) |
| Pipeline depth | 5 stages (IF / ID / EX / MEM / WB) |
| Integer register file | 32 × 32-bit,x0 恆為 0 |
| Floating-point register file | 32 × 32-bit,f0 可寫 |
| Program counter | 32-bit |
| Clock period | 2.0 ns(`script/DC.sdc` 與 `sim/top_tb.sv` 一致) |
| RTL simulation | prog0 / prog1 全部 PASS(隨機 IM/DM latency、多組 seed) |
| Total cell area (synthesized) | (於課程伺服器合成後填入) |
| Timing slack @ 2.0 ns | (於課程伺服器合成後填入) |

## Design Overview

本 CPU 採用經典五級管線(IF→ID→EX→MEM→WB),模組切分依照講義:
`Decoder`、`Imm_ext`、`LD_filter`、`Regfile`(整數/浮點各一,參數化共用)、
`ALU`(含 M/B/DSP)、`FPU`、`JB_unit`、CSR 計數器,控制邏輯(hazard/stall/flush)
集中在 `top.sv`。

- **IF**:PC + 取指 FSM。`im_req` 為單週期脈衝,等待 `im_valid` 期間若管線
  stall,指令先存入 buffer(講義要求 "latch it if the pipeline is stalled")。
  分支改向時若請求仍在途,以 `discard` 旗標丟棄回傳資料後再對新 PC 發出請求,
  確保「收到 valid 前不重發 req」。
- **ID**:解碼、立即值擴展、同時讀整數與浮點暫存器檔;operand 依指令型別
  選自整數或浮點 bank,之後的 forwarding 路徑共用。
- **EX**:ALU / FPU / MUL / CSR 讀值 / JB unit。所有運算元經 forwarding mux。
- **MEM**:DM 存取 FSM(req 脈衝 → 等 valid),store 資料依位址位移並產生
  active-low `dm_bit_en` byte mask;load 回傳經 `LD_filter` 對齊與延伸。
- **WB**:寫回整數或浮點暫存器檔;暫存器檔讀取埠具 write-through bypass,
  消除 distance-3 hazard。

### FPU(FADD.S / FSUB.S / FMIN.S / FMAX.S)

- 對齊-相加-正規化-RNE 捨入的單週期資料路徑;24-bit 尾數外加 guard/round/
  sticky 3 bits。加法進位時右移一位並保留 sticky;有效減法大量抵銷只發生在
  指數差 ≤ 1(此時 sticky 必為 0),左移正規化為精確運算,故捨入永遠正確。
- 規格特例:加/減結果恰為 0 時輸出 +0;FMIN/FMAX 以保序整數鍵
  (`x[31] ? ~x : x|0x8000_0000`)比較,-0 < +0。
- 以 30,056 筆(含方向性 corner case + 隨機)向量對 Python 黃金模型驗證全數通過。

### 特殊設計

- IF 與 MEM 的記憶體延遲重疊:IF FSM 獨立於管線 stall 繼續預取到 buffer,
  降低隨機延遲下的 CPI。
- 整數/浮點 operand 合流進同一條 forwarding 資料路徑(以 `uses_frs*` 旗標
  選 bank),硬體成本接近單一 bank 的 forwarding 網路。
- Load 資料在 `dm_valid` 當拍即經 LD_filter 直接 forward 給 EX,load 完成當拍
  管線即可前進,不額外損失一拍。

## Table 2 — Hazard Handling

| Hazard | Mechanism |
|---|---|
| IM handshake(長延遲取指) | IF FSM:req 單脈衝 → 等待 valid;期間 PC 凍結、IF/ID 不更新(等同講義 "freeze PC / freeze IF-ID");若管線 stall 則把指令 latch 進 buffer |
| DM handshake(長延遲存取) | MEM FSM:指令停留在 MEM、`mem_busy` 凍結 IF/ID、ID/EX、EX/MEM,MEM/WB 連續灌 bubble,直到 `dm_valid` |
| ALU→ALU RAW | 全旁路 forwarding:MEM→EX 與 WB→EX(整數與浮點皆有),regfile 讀埠再提供 WB 同拍 write-through |
| Load-use | ID/EX 偵測 EX 級 load 之 rd 與 ID 級來源重疊(整數與 FLW 分 bank 判斷),凍結 PC/IF/ID 一拍、ID/EX 灌 bubble;load 資料到 MEM 後由 MEM→EX forward |
| Control hazard(branch/jal/jalr) | 於 EX 解析(JB unit 使用 forwarded operands),taken 時 flush IF/ID 與 ID/EX(2 bubbles)並改向 PC;在途的 IM 請求以 discard 旗標作廢 |

## Verification

- Python 工具鏈:`tools/asm.py`(68 指令組譯器)、`tools/iss.py`(黃金 ISS)。
- `sim/prog0`:68 條指令全覆蓋 + forwarding 連鎖、load-use、各型分支
  taken/not-taken、JALR LSB 清除、非對齊 byte/half 存取、飽和/溢位 corner、
  FP 捨入與 ±0 特例;結束後比對全部 x/f 暫存器與資料記憶體。
- `sim/prog1`:浮點插入排序 + 累加(迴圈、副程式呼叫、密集 load-use 與 FP RAW)。
- 測試平台 IM/DM 以隨機 1–4 cycle latency 回應 req/valid 協定,多組 seed 全 PASS。
- CSR 計數值與微架構相關,prog0 僅驗證可執行性(讀出後覆寫再比對)。

## Lessons Learned

1. req/valid 握手與管線 stall 的互動是本次設計的核心:redirect(branch flush)
   發生在取指在途時,必須丟棄舊資料而不是重發請求,否則違反協定或取錯指令。
2. IEEE-754 加法器的捨入正確性可以由「大抵銷只發生在指數差 ≤ 1」這個性質
   嚴謹地簡化;用軟體黃金模型做大量隨機向量比對能快速抓到 GRS 處理錯誤。
3. 以 ISS 自動產生黃金值,比手算期望值可靠且可擴充;同一套流程可直接複用
   到課程提供的測資。

## Suggestions

- 講義可補充 CSR 計數器(rdcycle/rdinstret)在管線中讀取時點的定義,
  方便與黃金值精確比對。
- 建議提供 IM/DM latency 的範圍,利於學生自行壓力測試。
