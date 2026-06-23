// probe.c — can userspace open IOAVDisplayMemoryConcreteUserClient on the panel memories?
// Read-only: only opens/closes the connection, issues NO methods. Safe.
#include <stdio.h>
#include <string.h>
#include <mach/mach.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>

static void dump_prop(io_object_t svc, const char* key) {
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFTypeRef v = IORegistryEntryCreateCFProperty(svc, k, kCFAllocatorDefault, 0);
    CFRelease(k);
    if (!v) return;
    if (CFGetTypeID(v) == CFStringGetTypeID()) {
        char b[128]=""; CFStringGetCString((CFStringRef)v,b,sizeof b,kCFStringEncodingUTF8);
        printf("    %s = \"%s\"\n", key, b);
    }
    CFRelease(v);
}

int main(void) {
    io_iterator_t it;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("AppleTCONComponent"), &it) != KERN_SUCCESS) {
        printf("no AppleTCONComponent services\n"); return 1;
    }
    io_object_t svc;
    while ((svc = IOIteratorNext(it))) {
        io_name_t rn=""; IORegistryEntryGetName(svc, rn);
        printf("[node] %s\n", rn);
        dump_prop(svc, "IOUserClientClass");
        for (int type = 0; type < 3; type++) {
            io_connect_t conn = 0;
            kern_return_t kr = IOServiceOpen(svc, mach_task_self(), type, &conn);
            const char* s = kr==KERN_SUCCESS ? "OPENED OK" :
                kr==kIOReturnNotPrivileged ? "kIOReturnNotPrivileged (needs entitlement/root)" :
                kr==kIOReturnUnsupported   ? "kIOReturnUnsupported (wrong type)" :
                kr==kIOReturnBadArgument   ? "kIOReturnBadArgument" :
                kr==kIOReturnExclusiveAccess? "kIOReturnExclusiveAccess (busy)" : "other";
            printf("    open type=%d -> 0x%08x  %s\n", type, kr, s);
            if (kr==KERN_SUCCESS) { IOServiceClose(conn); break; }
        }
        IOObjectRelease(svc);
    }
    IOObjectRelease(it);
    return 0;
}
