// Read-only process and resource coalition metrics from Darwin.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

typedef int (*CoalitionUsageReader)(uint64_t, void *, size_t);

/// Returns a borrowed process-lifetime function pointer, or NULL if unavailable.
CoalitionUsageReader mm_resolve_usage_reader(void);
/// Writes the resource coalition for pid on success. coalition_id must be non-null.
bool mm_resource_coalition(pid_t pid, uint64_t *coalition_id);
/// Reads the coalition footprint in bytes with the resolved reader. bytes must be non-null.
bool mm_coalition_footprint(CoalitionUsageReader reader, uint64_t coalition_id, uint64_t *bytes);
/// Reads the process footprint in bytes. bytes must be non-null.
bool mm_process_footprint(pid_t pid, uint64_t *bytes);
