# RV32I 5-Stage Pipelined Processor (VHDL)

A fully synthesizable 5-stage RISC-V **RV32I** pipeline written in **VHDL-2008**,
targeting an Intel Cyclone V FPGA (`5CSEMA5F31C6`) with a 100 MHz timing constraint.
Verified by **29 self-checking testbenches**, from per-module unit tests up to an
end-to-end Fibonacci program.

## Microarchitecture

```
IF ──> ID ──> EX ──> MEM ──> WB
```

- **Full RV32I** — all 40 base instructions (R/I/S/B/U/J types; `FENCE`/`ECALL`/`EBREAK` retire as NOPs).
- **Hazard detection unit** — load-use hazards stall the front end for exactly 1 bubble.
- **2-stage forwarding** — `EX/MEM → EX` and `MEM/WB → EX` bypass paths eliminate RAW stalls.
- **Branch prediction** — 1-bit BHT, 16 entries, indexed by `PC[5:2]`.
- **Branches resolve in EX** — 2-cycle misprediction penalty with pipeline flush.
- **Harvard memory** — separate synchronous IMEM (ROM) and DMEM (RAM); both infer M10K blocks on Cyclone V. DMEM is byte-addressable and handles sign/zero extension for all load widths.
- Control signals are bundled into VHDL records (`ctrl_ex_t`, `ctrl_mem_t`, `ctrl_wb_t`) so pipeline registers stay readable.

## Layout

```
src/
  pkg_riscv.vhd        Opcodes, ALU codes, shared constants, control record types
  alu.vhd              32-bit ALU
  regfile.vhd          32x32 register file (x0 hardwired to 0, write-through forwarding)
  branch_predictor.vhd 1-bit branch history table
  hazard_unit.vhd      Load-use stall logic + forwarding mux selects
  imem.vhd             Instruction memory, initializable from a hex file via generic
  dmem.vhd             Data memory with load/store size and extension handling
  control_unit.vhd     Instruction decode -> control bundles + immediate generation
  pipeline_top.vhd     Top level: pipeline registers and full integration

tb/                    29 self-checking testbenches (see below)
sim/run_all.do         ModelSim script: compiles and runs the full suite
synth/                 Quartus project (.qsf) and 100 MHz timing constraints (.sdc)
```

## Verification

| Level | Testbenches |
|---|---|
| **Unit** | `alu`, `regfile`, `imem`, `dmem`, `control_unit`, `hazard_unit`, `branch_predictor` |
| **Instruction coverage** | `r_type` (all 10), `i_type` (all 9), `all_loads` (all 5, with sign/zero extension), `all_stores` (all 3), `branch` (all 6 taken), `branch_not_taken`, `lui_auipc`, `jal_jalr`, `fence_system` |
| **Hazards & forwarding** | `hazard_raw`, `hazard_load_use`, `forwarding` (exhaustive 2-stage coverage), `store_forward`, `branch_with_forwarding`, `consecutive_branches`, `pipeline_stall_count` |
| **Edge cases** | `overflow_edge`, `reset` |
| **End-to-end** | `full_fibonacci` — runs a Fibonacci program on the pipeline and checks `fib(10) = 55` |

Testbenches assemble their programs as hex arrays at runtime and pass them to IMEM
through the `INIT_FILE` generic, so no external toolchain is needed to run the suite.

## Simulating

```bash
# ModelSim / Questa
vsim -c -do sim/run_all.do
```

## Synthesizing

Open `synth/rv32i_pipeline.qsf` in Quartus Prime (Cyclone V,
`5CSEMA5F31C6`). `synth/rv32i_pipeline.sdc` constrains the clock to 100 MHz.

## Tech

VHDL-2008 · RISC-V RV32I · Intel Quartus Prime · ModelSim/Questa · Intel Cyclone V

## Known limitations

- Some branch and `JAL` hex encodings in the testbenches were hand-calculated; they are worth re-verifying against `riscv32-unknown-elf-as`.
- Synthesis results (ALM utilisation, Fmax) require a Quartus run and are not yet recorded here.
