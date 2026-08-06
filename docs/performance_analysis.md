# Performance Analysis

The final processor completed CoreMark with **304,044 committed instructions in 490,521 cycles**, producing an IPC of **0.6198**. Development followed a repeated cycle of profiling the current design, correcting the largest limitation, and measuring what became the next bottleneck.

## Final CoreMark Results

| Metric | Result |
|---|---|
| IPC | 0.6198 |
| Committed instructions | 304,044 |
| Total cycles | 490,521 |
| Empty-IQ bypass use | 278,957 cycles / 56.87% |
| Rename stalls | 58,184 cycles / 11.86% |
| Instructions issued | 313,163 cycles / 63.84% |
| Branch flushes | 4,591 / 0.936% of cycles |
| Average ROB occupancy | 17.0 / 32 entries |

## Major Improvements

### Frontend Delivery

An I-cache response originally had to enter an empty instruction queue before being sent to decode on the following cycle. The final design forwards the response directly when the queue is empty and decode is ready.

This bypass was used during **56.87%** of the run. It removed an unnecessary queue delay, although the frontend could still run out of instructions while waiting for later I-cache responses.

### Instruction Window and Scheduling

The ROB and reservation station were expanded from 16 to 32 entries, allowing the processor to keep more instructions in flight and issue around stalled operations. The reservation station was also redesigned with a balanced network for selecting the oldest ready instruction.

The final reservation station caused no rename stalls, showing that its original capacity limit was removed. Remaining instruction-window pressure came mainly from the ROB and free list rather than the reservation station.

### Memory Scheduling

The split load and store queues allow loads to execute before older stores when no address conflict exists. Stores can also forward matching bytes directly to dependent loads.

The load queue searches for the oldest safe load rather than requiring strict queue-order execution. This exposed more memory parallelism, although load queue capacity could still block rename during parts of the benchmark.

### Completion Handling

Completed execution results are buffered when the shared completion path is occupied. Entries remain in the FSU queue until they can be accepted, and results belonging to flushed instructions are discarded.

The FSU queue became full for only one cycle, so its capacity was no longer a meaningful bottleneck. However, normal writeback still competed with load and store completion for the shared completion path.

## Remaining Bottlenecks

The remaining limitations are the parts of each subsystem that were not addressed by the current optimizations.

| Limitation | Profiler evidence | Most likely next step |
|---|---|---|
| Frontend response gaps | 54,329 cycles with no usable instruction while rename was ready | Fetch two adjacent instructions per I-cache response |
| Completion and ROB pressure | Writeback delayed for 32,666 cycles and ROB full for 95,425 cycles | Add a second CDB or separate load completion path, then remeasure ROB pressure |
| Free register pressure | Free list reached zero and blocked rename for 20,000 cycles | Increase the physical register file if completion improvements do not relieve the pressure |
| Integer issue availability | 30,146 cycles with a ready RS entry but no issue | Measure actual ALU acceptance before deciding whether a second ALU is justified |
| Load queue capacity | LQ full contributed to 12,383 rename stall cycles | Increase LQ capacity or support more concurrent load activity |

A larger ROB or wider commit stage may help, but the current data does not show that either is the first change to make. Improving completion bandwidth could allow instructions to finish and retire sooner, reducing ROB and free-list pressure without increasing those structures.

## Summary

The final design reached **0.6198 IPC** by removing unnecessary frontend latency, expanding the instruction window, improving memory scheduling, and making completion handling robust under contention. These changes eliminated several earlier bottlenecks, while profiling exposed narrower remaining limits in fetch bandwidth, completion bandwidth, register availability, and execution capacity.
