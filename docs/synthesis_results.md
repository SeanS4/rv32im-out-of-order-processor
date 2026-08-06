# Synthesis Results

The processor was synthesized with Synopsys Design Compiler using the Nangate 45 nm standard-cell library and SRAM macros for the instruction and data caches. Despite the complexity of the out-of-order scheduling, rename, branch prediction, and memory structures, the final design met its 100 MHz timing target.

## Summary

| Metric | Result |
|---|---|
| Clock target | 10.000 ns / 100 MHz |
| Worst-case setup slack | +0.007241 ns / +7.241 ps |
| Total synthesized cell area | 439,721 µm² / 0.440 mm² |
| Total cells | 159,964 |
| Combinational cells | 129,955 |
| Sequential cells | 29,231 |
| SRAM macros | 16 |

## Timing

The final implementation met the 10 ns clock target with **7.2 ps of positive setup slack**.

The critical path now runs from FSU queue writeback selection through same-cycle branch resolution and flush handling. This became the longest path only after the reservation station was redesigned to reduce its combinational delay.

Balancing the scheduler preserved oldest-ready issue and same-cycle CDB wakeup while removing the reservation station as the processor’s timing bottleneck.

## Area

The final synthesized design occupies 439,721 µm², or approximately 0.440 mm², of cell area.

| Cell category | Area | Percentage |
|---|---|---|
| Combinational logic | 153,617 µm² | 34.94% |
| Sequential logic | 132,121 µm² | 30.05% |
| SRAM macros | 153,984 µm² | 35.02% |

The area is distributed almost evenly among combinational logic, sequential storage, and SRAM macros. The instruction and data caches together account for approximately 38.5% of total cell area. The largest non-cache structures are the reservation station, reorder buffer, and TAGE predictor.

These area figures come from synthesis before the cells were physically placed and connected, so the completed layout would be larger.

## Supporting Reports

| Report | Description |
|---|---|
| [`timing.rpt`](../reports/timing.rpt) | Complete worst-case timing paths |
| [`area.rpt`](../reports/area.rpt) | Cell counts and hierarchical area breakdown |
| [`synthesis.log`](../reports/synthesis.log) | Design Compiler synthesis and optimization log |
