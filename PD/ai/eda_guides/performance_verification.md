# Performance Verification

## Overview

Performance verification ensures that a digital design meets its throughput, latency, bandwidth, and efficiency requirements under realistic operating conditions. While functional verification confirms that the design produces correct outputs, performance verification confirms that it does so within the specified time and resource constraints. Performance bugs — designs that are functionally correct but fail to meet throughput or latency targets — can be as fatal as functional bugs and are often harder to detect because they emerge only under specific traffic patterns and system loads.

## Latency Measurement

### Definition

Latency is the time elapsed between a stimulus entering the design and the corresponding response appearing at the output. Latency measurements must account for:

- **Request-to-response latency**: Total time from request issuance to response receipt.
- **Pipeline latency**: Fixed latency through a pipeline (deterministic).
- **Queuing latency**: Variable latency due to waiting in buffers and arbiters (stochastic).
- **Worst-case latency**: Maximum latency under adversarial conditions.
- **Average latency**: Mean latency across a representative traffic profile.

### Latency Measurement Infrastructure

```systemverilog
class latency_monitor extends uvm_subscriber #(my_transaction);
  // Track request timestamps
  int unsigned request_time[int];  // Keyed by transaction ID

  // Statistics
  int unsigned latency_samples[$];
  int unsigned min_latency = '1;
  int unsigned max_latency = 0;
  real         avg_latency = 0;

  function void record_request(my_transaction txn);
    request_time[txn.id] = $time;
  endfunction

  function void record_response(my_transaction txn);
    int unsigned latency;
    if (request_time.exists(txn.id)) begin
      latency = $time - request_time[txn.id];
      latency_samples.push_back(latency);
      if (latency < min_latency) min_latency = latency;
      if (latency > max_latency) max_latency = latency;
      avg_latency = real'(latency_samples.sum()) / latency_samples.size();
      request_time.delete(txn.id);

      // Assert latency requirement
      assert (latency <= MAX_ALLOWED_LATENCY)
        else `uvm_error("LATENCY", $sformatf(
          "Transaction %0d latency %0d exceeds limit %0d",
          txn.id, latency, MAX_ALLOWED_LATENCY))
    end
  endfunction
endclass
```

### Latency Coverage

```systemverilog
covergroup cg_latency with function sample(int unsigned latency);
  cp_latency: coverpoint latency {
    bins fast      = {[1:10]};
    bins normal    = {[11:50]};
    bins slow      = {[51:100]};
    bins very_slow = {[101:$]};
  }
endgroup
```

### Latency Profiling

Track latency distribution across different conditions:
- By transaction type (read vs. write).
- By address range (cached vs. uncached).
- By traffic load (light vs. heavy).
- By arbitration priority (high vs. low priority).

## Throughput Verification

### Definition

Throughput measures the rate at which the design processes data, typically expressed in transactions per second, bytes per second, or operations per clock cycle.

### Throughput Measurement

```systemverilog
class throughput_monitor extends uvm_component;
  int unsigned transaction_count = 0;
  int unsigned byte_count = 0;
  int unsigned start_time;
  int unsigned measurement_window;

  function void record_transaction(my_transaction txn);
    transaction_count++;
    byte_count += txn.data.size();
  endfunction

  function void report_phase(uvm_phase phase);
    real elapsed_cycles = ($time - start_time) / CLOCK_PERIOD;
    real txn_per_cycle = real'(transaction_count) / elapsed_cycles;
    real bytes_per_cycle = real'(byte_count) / elapsed_cycles;

    `uvm_info("THROUGHPUT", $sformatf(
      "Throughput: %.2f txn/cycle, %.2f bytes/cycle (%.1f%% of theoretical max)",
      txn_per_cycle, bytes_per_cycle,
      (bytes_per_cycle / MAX_BW_PER_CYCLE) * 100.0), UVM_LOW)

    // Assert minimum throughput
    assert (bytes_per_cycle >= MIN_REQUIRED_BW)
      else `uvm_error("THROUGHPUT",
        $sformatf("Throughput %.2f below minimum %.2f",
                  bytes_per_cycle, MIN_REQUIRED_BW))
  endfunction
endclass
```

### Sustained vs. Burst Throughput

- **Burst throughput**: Maximum data rate over a short window (typically limited by pipeline width and bus width).
- **Sustained throughput**: Average data rate over a long window (limited by memory bandwidth, arbitration overhead, and protocol efficiency).

Both must be measured and verified against requirements.

### Throughput Under Contention

Measure throughput when multiple requestors compete for shared resources:
- N masters accessing a shared bus.
- Multiple DMA channels using the same memory port.
- Read/write interleaving on a memory controller.

## Bandwidth Analysis

### Bandwidth Components

Total bandwidth is determined by:
- **Protocol efficiency**: Useful data bytes / total bytes on the bus (headers, idle cycles reduce efficiency).
- **Bus utilization**: Percentage of clock cycles where the bus carries data.
- **Memory subsystem bandwidth**: Read/write bandwidth to external memory.
- **Interconnect bandwidth**: Total fabric throughput across all ports.

### Bandwidth Measurement

```systemverilog
class bandwidth_monitor extends uvm_component;
  int unsigned data_bytes_in_window = 0;
  int unsigned cycles_in_window = 0;
  int unsigned window_size = 1000;  // Measurement window in cycles

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      cycles_in_window++;
      if (vif.valid && vif.ready)
        data_bytes_in_window += count_data_bytes(vif.data);

      if (cycles_in_window == window_size) begin
        real bandwidth = real'(data_bytes_in_window) / cycles_in_window;
        cg_bw.sample(bandwidth);

        // Check against requirement
        if (bandwidth < min_required_bandwidth)
          `uvm_warning("BW", $sformatf("Bandwidth %.2f below target %.2f",
                       bandwidth, min_required_bandwidth))

        data_bytes_in_window = 0;
        cycles_in_window = 0;
      end
    end
  endtask
endclass
```

### Bandwidth Coverage

```systemverilog
covergroup cg_bandwidth with function sample(real bandwidth);
  cp_bw: coverpoint int'(bandwidth * 100) {
    bins idle      = {[0:10]};
    bins low       = {[11:30]};
    bins moderate  = {[31:60]};
    bins high      = {[61:85]};
    bins saturated = {[86:100]};
  }
endgroup
```

## Bottleneck Identification

### Common Bottlenecks

1. **Arbitration delays**: Unfair or inefficient arbitration starves some requestors.
2. **Buffer full conditions**: FIFOs filling up causes backpressure that propagates upstream.
3. **Memory bandwidth limitation**: External memory access time limits overall throughput.
4. **Protocol overhead**: Handshaking, header processing, and idle cycles reduce effective bandwidth.
5. **Credit-based flow control**: Insufficient credits limit outstanding transactions.
6. **Serialization points**: Single-resource bottlenecks (single-ported memory, shared bus).

### Bottleneck Detection Metrics

```systemverilog
// Monitor FIFO occupancy (bottleneck indicator)
always @(posedge clk) begin
  if (fifo_count > FIFO_DEPTH * 0.9)
    high_watermark_count++;
end

// Monitor arbiter grant starvation
always @(posedge clk) begin
  if (request && !grant)
    wait_cycles[requester_id]++;
end

// Monitor backpressure
always @(posedge clk) begin
  if (valid && !ready)
    backpressure_cycles++;
end
```

### Performance Assertions

```systemverilog
// Assert maximum queuing time (prevent starvation)
AST_NO_STARVATION: assert property (@(posedge clk)
  request[0] |-> ##[0:MAX_WAIT] grant[0]
) else $error("Requester 0 starved for %0d cycles", MAX_WAIT);

// Assert minimum throughput in a window
sequence s_measure_window;
  @(posedge clk) ##[0:WINDOW_SIZE-1] 1;
endsequence

// Assert FIFO never overflows under normal operation
AST_FIFO_NO_OVERFLOW: assert property (@(posedge clk) disable iff (reset)
  fifo_count < FIFO_DEPTH
);
```

## Performance Test Strategy

### Traffic Profiles

Define realistic traffic profiles based on use cases:

**Streaming profile**: Continuous, sequential, write-heavy traffic (video, camera).
```systemverilog
constraint c_streaming {
  txn.burst_type == INCR;
  txn.burst_length == 16;
  txn.addr == prev_addr + (16 * data_width / 8);
  txn.write == 1;
  txn.delay inside {[0:2]};
}
```

**Random access profile**: Small, random reads with occasional writes (CPU cache miss pattern).
```systemverilog
constraint c_random_access {
  txn.burst_length inside {1, 2, 4};
  txn.write dist { 0 := 80, 1 := 20 };  // Read-heavy
  txn.delay inside {[0:10]};
}
```

**Mixed profile**: Combination of streaming and random access from multiple masters.

### Performance Regression

- Run performance tests with fixed seeds for reproducible comparison.
- Track performance metrics across RTL versions.
- Flag performance regressions (degradation from previous build).
- Compare measured performance against specification requirements.

## Performance Verification on Emulation

Software simulation is too slow for meaningful performance measurement of SoC-level workloads. Emulation and FPGA prototyping provide:
- Real firmware execution for realistic traffic generation.
- Sustained workload execution (minutes to hours of simulated time).
- Multiple concurrent traffic sources operating simultaneously.
- Performance counter extraction for cycle-accurate measurement.

## Queueing Theory for Performance Analysis

### Little's Law

```
L = lambda * W
```
Where L = average items in system, lambda = arrival rate, W = average time in system.

This fundamental relationship helps verify that the design's queuing behavior matches analytical models.

### Utilization Analysis

```
Utilization (rho) = Arrival rate / Service rate
```

When utilization approaches 1.0, queuing delays grow exponentially. The design must maintain utilization below the target to meet latency requirements.

## Best Practices

1. **Define performance requirements quantitatively** in the specification (latency in cycles, bandwidth in bytes/cycle, throughput in transactions/second).
2. **Build performance monitors into the testbench** from the beginning, not as an afterthought.
3. **Use realistic traffic profiles** derived from actual use cases, not just uniform random.
4. **Measure under varying load conditions** to characterize performance across the operating range.
5. **Track performance metrics across builds** to detect regressions early.
6. **Use emulation for system-level performance verification** when simulation is too slow.

## Summary

Performance verification confirms that the design meets its throughput, latency, and bandwidth requirements. Latency monitors track request-to-response timing. Throughput monitors measure data rates. Bandwidth analysis identifies utilization patterns. Bottleneck detection pinpoints the limiting factors. Realistic traffic profiles and systematic performance assertions ensure that performance is verified under representative conditions. Performance verification complements functional verification to provide complete confidence in the design's fitness for its intended application.
