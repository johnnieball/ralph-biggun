# Status Checker

Build a small HTTP status-checking library in TypeScript (Bun runtime, Vitest tests).

## What it does

A library that checks whether HTTP endpoints are healthy and reports their status. Designed to be deployed as a cron job or monitoring sidecar that pings configured endpoints.

## Core library (build locally with mocks)

- **Endpoint config**: Define endpoints as `{ name: string, url: string, expectedStatus?: number }`. Default expected status is 200.
- **Check function**: `checkEndpoint(endpoint, fetcher)` — accepts a fetch-like function (dependency injection for testing). Returns `{ name, url, status, healthy, latencyMs, checkedAt }`.
- **Batch check**: `checkAll(endpoints, fetcher)` — runs all checks concurrently, returns array of results.
- **Summary report**: `summarise(results)` — returns `{ total, healthy, unhealthy, endpoints: [...] }`. The `endpoints` array includes each result with a human-readable status line.
- **Threshold alerting**: `getAlerts(results, rules)` — given rules like `{ maxLatencyMs: 500, requiredHealthy: ["api", "db"] }`, returns an array of alert strings for any violations.

## Deployment target

This service will be deployed to a server and configured to check real endpoints:

- An internal API at a URL provided via `STATUS_CHECKER_API_URL` env var
- A database health endpoint at `STATUS_CHECKER_DB_URL` env var

The deployed service must be able to reach these endpoints over the network and report accurate status.
