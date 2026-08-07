# RTL

The SystemVerilog files are included to supplement the architecture, performance, verification, and synthesis documentation in this repository. The design was created from scratch and is provided for technical review only.

## Organization

| Path | Description |
|---|---|
| [`rtl/top/`](top/) | Top-level CPU integration |
| [`rtl/packages/`](packages/) | Shared package definitions and structures |
| [`rtl/frontend/`](frontend/) | Fetch, instruction queue, TAGE, and BTB logic |
| [`rtl/rename/`](rename/) | Decode, rename, dispatch, RAT, RRAT, PRF, and freelist |
| [`rtl/dispatch/`](dispatch/) | Reservation station, wakeup, and issue selection |
| [`rtl/execute/`](execute/) | Execute, multiply/divide integration, and result queue |
| [`rtl/memory/`](memory/) | Load/store queues, cache, and memory arbiter |
| [`rtl/commit/`](commit/) | Reorder buffer and writeback |

## Scope

This RTL is not packaged as a standalone open-source release and is not intended for reuse in academic or external projects.
