// tcontool.m — call AppleDisplayTCONControl's ADIOReportingInterface to read panel serial.
// Read-only reporting calls (getDeviceInfo / getSerialNumber / getDiagnosticData / getTCONRegs).
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>

static id call0(id obj, const char* sel) {
    SEL s = sel_registerName(sel);
    if (![obj respondsToSelector:s]) return @"(no selector)";
    @try { return ((id(*)(id,SEL))objc_msgSend)(obj, s); }
    @catch (NSException* e) { return [NSString stringWithFormat:@"(exc: %@)", e]; }
}

int main(int argc, char** argv) {
    @autoreleasepool {
        const char* fw = "/System/Library/PrivateFrameworks/AppleDisplayTCONControl.framework/AppleDisplayTCONControl";
        if (!dlopen(fw, RTLD_NOW)) { printf("dlopen: %s\n", dlerror()); return 1; }
        Class C = objc_getClass("ADIOReportingInterface");
        if (!C) { printf("no ADIOReportingInterface\n"); return 1; }

        NSMutableArray* cands = [@[ @"disp0", @"", @"disp0@8A000000", @"AppleCLCD2", @"internal" ] mutableCopy];
        if (argc > 1) [cands insertObject:@(argv[1]) atIndex:0];

        // also try nil
        for (NSInteger i = -1; i < (NSInteger)cands.count; i++) {
            NSString* cid = (i < 0) ? nil : cands[i];
            id inst = ((id(*)(id,SEL))objc_msgSend)((id)C, sel_registerName("alloc"));
            inst = ((id(*)(id,SEL,id))objc_msgSend)(inst, sel_registerName("initWithContainerID:"), cid);
            if (!inst) { printf("\n[containerID=%s] init -> nil\n", cid?cid.UTF8String:"(nil)"); continue; }
            printf("\n========== containerID = %s ==========\n", cid?cid.UTF8String:"(nil)");
            printf("getDeviceInfo    : %s\n", [[NSString stringWithFormat:@"%@", call0(inst,"getDeviceInfo")] UTF8String]);
            printf("getSerialNumber  : %s\n", [[NSString stringWithFormat:@"%@", call0(inst,"getSerialNumber")] UTF8String]);
            printf("getTCONFWVersion : %s\n", [[NSString stringWithFormat:@"%@", call0(inst,"getTCONFWVersion")] UTF8String]);
            id diag = call0(inst, "getDiagnosticData");
            NSString* ds = [NSString stringWithFormat:@"%@", diag];
            if (ds.length > 800) ds = [[ds substringToIndex:800] stringByAppendingString:@" …(truncated)"];
            printf("getDiagnosticData: %s\n", ds.UTF8String);
        }
    }
    return 0;
}
