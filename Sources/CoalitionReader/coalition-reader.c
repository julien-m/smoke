// Isolates the private ABI observed in loginwindow on macOS 26.5.
#include "coalition-reader.h"
#include <dlfcn.h>
#include <libproc.h>
#include <sys/resource.h>

enum {
    // XNU sys/proc_info_private.h and mach/coalition.h.
    pid_coalition_info = 20,
    coalition_resource_index = 0,
    coalition_id_slots = 5,
    footprint_index = 0x140 / sizeof(uint64_t),
    usage_slots = 0x168 / sizeof(uint64_t),
};

CoalitionUsageReader mm_resolve_usage_reader(void) {
    return (CoalitionUsageReader)dlsym(RTLD_DEFAULT, "coalition_info_resource_usage");
}

bool mm_resource_coalition(pid_t pid, uint64_t *coalition_id) {
    uint64_t fields[coalition_id_slots] = {0};
    int size = proc_pidinfo(pid, pid_coalition_info, 0, fields, sizeof(fields));
    if (size != sizeof(fields) || fields[coalition_resource_index] == 0) {
        return false;
    }
    *coalition_id = fields[coalition_resource_index];
    return true;
}

bool mm_coalition_footprint(CoalitionUsageReader reader, uint64_t coalition_id, uint64_t *bytes) {
    uint64_t fields[usage_slots] = {0};
    if (reader == NULL || reader(coalition_id, fields, sizeof(fields)) != 0) {
        return false;
    }
    *bytes = fields[footprint_index];
    return true;
}

bool mm_process_footprint(pid_t pid, uint64_t *bytes) {
    struct rusage_info_v0 info = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V0, (rusage_info_t *)&info) != 0) {
        return false;
    }
    *bytes = info.ri_phys_footprint;
    return true;
}
