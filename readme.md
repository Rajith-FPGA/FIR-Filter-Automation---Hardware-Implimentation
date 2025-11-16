# 🎧 FPGA-DSP Audio Filter Automation Project — Hardware Implementation  
## (Phases 1–3: Simulation → Parallelization → Real-Time ADC/DAC)
> # 📌 Project Status November 15 2025 Phase 2 Done
> ## ⚠️ Phase 1 Bug Summary and Phase 2 Fixes  
> ### (Important Engineering Note — Verified and Corrected in Phase 2)
> 
> This repository originally contained two major issues in the **Phase 1 behavioral FIR implementation**, which led to incorrect filtering results even though the early charts appeared correct.  
> These issues were fully diagnosed and resolved in **Phase 2**, and the corrected hardware now matches the Python golden model.
> 
> ---
> 
> ## 🟥 1. Phase 1 Address Generator Errors  
> The symmetric memory addressing logic was incorrect in multiple ways:
> 
> ### ❌ 1.1 Left and right pointers fell out of sync  
> - Left pointer did not decrement at the correct cycles  
> - Right pointer incremented early  
> - Resulting (xL, xR) sample pairs did **not** correspond to the correct tap index

> ### ❌ 1.2 Incorrect wrap-around at boundaries  
> - Pointer resets did not occur at exact 0 and 316  
> - Some taps reused stale samples from previous batches  

> ### ❌ 1.3 Batch-to-batch pointer drift  
> - Each k-index cycle did not realign cleanly  
> - Caused non-deterministic tap pair sequences  
> 
> **Impact:**  
> The FIR MAC received incorrect sample pairs → incorrect partial sums → incorrect final FIR output.
> 
> ---
> 
> ## 🟥 2. Phase 1 Verification Mistake (Fully Admitted and Corrected)  
> A critical evaluation mistake occurred:
> 
> ### ❌ The initial “SNR” and “impulse response” charts compared  
> **Python output vs Python output**  
> instead of  
> **Verilog output vs Python reference**.
> 
> Meaning: the early report unintentionally validated Python against itself — not the FPGA.
> 
> This created a false sense of correctness while the Phase 1 hardware was still wrong.
> 
> ---
> 
> # 🟩 Phase 2: Full Resolution and Correct Hardware Output  
> 
> ### 🟢 3. Completely Redesigned Address Generator  
> - True symmetric sequence validated:  
>   (316,0), (315,1), …, (158,158)  
> - Correct wrap logic at edges  
> - Deterministic pointer alignment for all 159 tap pairs  
> 
> ### 🟢 4. Explicit DSP48E1 MAC With Correct INMODE  
> - Correct AREG/BREG/DREG/MREG/PREG configuration  
> - Fixed coefficient selection bug (INMODE[4] = 0 → correct B2 path)  
> - Verified MAC1 → MAC2 → accumulator dataflow
> 
> ### 🟢 5. Correct Verification Rebuilt From Scratch  
> - True **Python vs Verilog** comparison  
> - Impulse response generated from **Verilog output**, not Python  
> - All 317 taps match expected shape  
> - Final filtered output matches Python within **±1 LSB**  
> - SNR ≈ **49.7 dB**, fully quantization-limited  
> 
> ---
> 
> # 🟦 ✔ Final Status  
> Phase 1 issues are fully resolved.  
> Phase 2 hardware is **correct, stable, pipelined, and matches the Python golden model**.  
> This forms the verified foundation for **Phase 3 (Real-Time ADC/DAC) — Target: Nov 30**.
> 
> ### 📌 Project Status November 10 2025 (Second Update)
> Currently in **Multiplexing & Parallelization** phase — optimizing the 317-tap FIR core for timing closure and DSP efficiency on the Spartan-7.
>
> **🧩 Architecture Update**
> - Original build ran **4 parallel MACs at 400 MHz** with dual-read BRAM.  
> - Timing violations confirmed this exceeds practical fabric limits.  
> - Architecture now shifting to **200 MHz time-multiplexed MAC scheduling** for stable closure and resource efficiency.
> - 
> **⚙️ Timing Closure (400 MHz Attempt)**
> - Vivado showed **setup violations (~ –3.3 ns WNS)** between BRAM → DSP paths.  
> - BRAM18E1 itself failed 2.5 ns period (≈ –0.44 ns slack).  
> - Confirms Spartan-7 cannot sustain true 400 MHz with memory access.  
> - Realistic range: **200–300 MHz** depending on routing.
> 
> **🔧 Next Step**
> ✅ Retarget to **200 MHz**, maintain throughput using **time-multiplexed MAC reuse**.  
> Focus: clean timing, reduced fan-out, and production-feasible FPGA mapping.



> ## ⚙️ Project Status Update – November 10 2025
>
> **Current Phase:** Multiplexing and Parallelizing the FIR Core  
> **Status:** Integrating 4-way parallel MAC operation and verifying synchronization between 400 MHz (compute) and 100 MHz (control) domains.  
>
> **Challenges Encountered:**  
> - Cross-domain timing violations (400 ↔ 100 MHz / 12.288 MHz) during synthesis.  
> - Implementing safe CDC (FIFO / handshake) and pipelining to achieve stable timing at 400 MHz.  
> - FSM coordination for parallel MAC activation and accumulation sequencing.  
>
> **Next Milestone:**  
> ✅ Achieve clean timing closure and verified multi-clock FSM behavior for parallel MACs.  
> 🎯 **Target Delivery:** **November 13 2025**


## 🚀 Overview  
This repository continues the **FPGA-DSP Audio Filter Automation Project**, which originally automated FIR filter design, analysis, and ranking in Python.  
Here, that same 317-tap low-pass Hamming filter (3 kHz @ 48 kHz fs) is implemented and verified in **hardware** on the **Arty S7-50 FPGA**.  
The goal is to bridge automated DSP theory with real-world digital design — from floating-point Python simulation to bit-true, cycle-accurate Verilog and full audio-chain testing.

---

## 📂 Repository Structure  
docs/ → Engineering reports, timing/utilization summaries
/src/ → Verilog source modules (sample_mem, mac_unit, fir_core, etc.)| .mem input files
/sim/ → Testbench 
/results/ → verilog_out.txt


---

## 🧩 Phase 1 — Simulation & Verification ✅  
**Objective:** Validate the 317-tap FIR filter behavior entirely in simulation.  

- Fully behavioral Verilog model tested in **ModelSim**  
- Input: real 48 kHz audio samples (`input_clip_48k_fixed.mem`)  
- Output verified vs ideal Python reference  
- Measured latency = 158 samples (≈ 3.29 ms)  
- Achieved SNR ≈ 80 dB vs ideal FIR model  
- Timing met at 100 MHz system clock  

**Key documents:**  
- `/docs/FPGA_FIR_Filter_Verification_Phase1_Clean.pdf`  
- `/docs/FPGA_FIR_Signal_Analysis_Report.pdf`  

**Results snapshot**

| Metric | Value | Verdict |
|---------|--------|---------|
| FIR Order | 317 taps | ✅ Verified |
| Cutoff Freq | 3 kHz @ 48 kHz fs | ✅ Matches design |
| Group Delay | 158 samples (3.29 ms) | ✅ Correct |
| SNR vs Ideal | ≈ 80 dB | ✅ Excellent |
| DC Offset | ≈ 0 | ✅ None |
| Peak Gain Ratio | ≈ 1.00 | ✅ Unity |
| DSP Usage | 1 / 120 DSP48E1 | ✅ Minimal |
| Timing @ 100 MHz | Passed | ✅ |

---

## ⚙️ Phase 2 — Parallelization (Performance Scaling) 🚀  
**Goal:** Increase throughput using multi-lane MAC parallelism.  

Planned upgrades:
- Replace single-MAC architecture with **4-MAC parallel FIR core**.  
- Split coefficient and sample memory into 4 segments (SIMD-style).  
- Use **DSP48E1 chaining** for internal accumulation.  
- Optimize FSM for pipelined execution (1 sample per 12.5 ns effective).  
- Add performance comparison between 1-MAC vs 4-MAC versions.  

**Deliverables**
- New branch: `phase2_parallel`  
- Updated timing/utilization report  
- Comparative runtime analysis (cycles per sample, throughput)  
- `FPGA_FIR_Phase2_Report.pdf`

---

## 🎙️ Phase 3 — Real-Time ADC/DAC Integration 🧩  
**Goal:** Demonstrate full hardware-in-loop audio filtering.  

**Target signal chain:**  
`ADC → FPGA (FIR Core) → DAC → Logic Analyzer`  

Planned features:
- Configure **FPGA as I²S master** to drive ADC/DAC.  
- Generate BCLK and LRCLK from internal 12.288 MHz PLL.  
- Stream live 48 kHz audio through FIR in real time.  
- Verify filtered output using **24 MHz logic analyzer**.  
- Compare captured waveform vs Python golden reference.  

**Deliverables**
- I²S controller module + `.xdc` pin mapping  
- Real-time demo recording + logic analyzer screenshots  
- `Phase3_RealTime_Test_Report.pdf`

---

## 🧠 Engineering Achievements  
| Capability | Status |
|-------------|---------|
| Verified FIR Convolution (317 taps) | ✅ |
| Accurate Group Delay = 158 samples | ✅ |
| Bit-True Match to Python Model | ✅ |
| Frequency Response Match | ✅ |
| Hardware Timing Met @ 100 MHz | ✅ |
| Resource Use < 2 % DSP48E1 | ✅ |
| Ready for Parallel Extension | 🚀 |
| Real-Time I/O Planned | ⏳ Phase 3 |

---

## 🧰 Tools & Environment  
- **Vivado 2025.1** (Arty S7-50 – xc7s50csga324-1)  
- **Vivado 2025.1 Simulation** for simulation and waveform debug  
- **Python 3.10** for DSP coefficient generation and verification  
- **24 MHz 8-ch Logic Analyzer** for hardware validation  
- **Git + GitHub** for phase-based project versioning  

---

## 🔮 Future Extensions  
- Add band-pass and high-pass FIR variants using same framework.  
- Extend to 2-D image FIR kernels (Phase 4).  
- Package as a reusable Vivado IP core for audio and sensor applications.  
- Publish FPGA + Python learning workflow for new DSP engineers.  

---

## 👤 Author  
**Rajith Senaratna**  
FPGA / DSP Design Engineer in Training  


