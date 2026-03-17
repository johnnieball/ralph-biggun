# Task Queue Library

Build an async task queue library in TypeScript (Bun runtime, Vitest tests).

## Overview

A job processing system where you can create jobs with async handlers, execute them, and manage them through a queue with concurrency control. Think of it like a simplified Bull/BullMQ but in-memory.

## Core Concepts

### Jobs

A job has a name, an async handler function, and goes through lifecycle states: pending → running → completed/failed. Jobs get unique IDs and track timestamps (created, started, completed).

If a job's handler throws, the job fails and the error is stored on it.

You shouldn't be able to execute a job that's not in pending state.

### Retry Logic

Jobs can optionally have a retry policy with maxRetries and delayMs. When a job fails and has retries left, it automatically re-executes after the delay. The job goes back to pending between retries. Track the attempt number. After all retries are exhausted, the job is permanently failed with all error messages preserved.

### Event System

Users can register callbacks that fire when a job's state changes. Callbacks receive the job ID, previous status, new status, and a timestamp. Multiple callbacks per job, invoked in registration order. If a callback throws, it shouldn't affect other callbacks or job execution.

### Queue with Concurrency

Instead of executing jobs directly, they go into a queue that processes N jobs at a time. FIFO order, with the next queued job starting as slots free up. The queue should expose stats (pending/running/completed/failed counts) and a drain() method that resolves when all jobs finish.

### Logging

All state transitions get logged to a file as JSON lines. The logger should be injected as a dependency, not hardcoded. Provide a default FileLogger. If logging fails, jobs should still work fine.

### Timeouts

Jobs can have a timeout. If the handler doesn't resolve in time, the job fails with a TimeoutError. Pass an AbortController signal to the handler so it can respond to cancellation. Timed-out jobs should still retry if they have retries left.

### Priority

Jobs can have a priority (integer, higher = more important, default 0). When a concurrency slot opens, the highest-priority pending job goes next. Same priority = FIFO. Existing FIFO behaviour should be preserved as the default.

### Graceful Shutdown

The queue should support graceful shutdown: finish running jobs but don't start new ones. Jobs added after shutdown are rejected. Running jobs that fail during shutdown are not retried. Shutdown is idempotent.

### Typed Results

Jobs should be generic — createJob<T> where T is the handler's return type. Completed jobs have a result field with the return value. Include a toJSON() method for serialisation.
