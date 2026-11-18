// Read-only process and resource coalition metrics from Darwin.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

typedef int (*CoalitionUsageReader)(uint64_t, void *, size_t);

CoalitionUsageReader mm_resolve_usage_reader(void);
bool mm_resource_coalition(pid_t pid, uint64_t *coalition_id);
bool mm_coalition_footprint(CoalitionUsageReader reader, uint64_t coalition_id, uint64_t *bytes);
bool mm_process_footprint(pid_t pid, uint64_t *bytes);
