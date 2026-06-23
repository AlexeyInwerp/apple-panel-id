// objcdump.m — load AppleDisplayTCONControl and enumerate its ObjC classes + methods.
#import <dlfcn.h>
#import <stdio.h>
#import <objc/runtime.h>

static void list(const char* path) {
    void* h = dlopen(path, RTLD_NOW);
    if (!h) { printf("dlopen failed: %s\n", dlerror()); return; }
    unsigned n = 0;
    const char** names = objc_copyClassNamesForImage(path, &n);
    printf("== %u classes in %s ==\n", n, path);
    for (unsigned i = 0; i < n; i++) {
        Class c = objc_getClass(names[i]);
        printf("\n@interface %s : %s\n", names[i], class_getName(class_getSuperclass(c)));
        unsigned mc = 0;
        Method* m = class_copyMethodList(c, &mc);
        for (unsigned j = 0; j < mc; j++) {
            const char* e = method_getTypeEncoding(m[j]);
            printf("  - %-44s  %s\n", sel_getName(method_getName(m[j])), e?e:"");
        }
        free(m);
        // class methods
        Class meta = object_getClass((id)c);
        unsigned cmc = 0; Method* cm = class_copyMethodList(meta, &cmc);
        for (unsigned j = 0; j < cmc; j++)
            printf("  + %-44s  %s\n", sel_getName(method_getName(cm[j])), method_getTypeEncoding(cm[j])?:"" );
        free(cm);
        // ivars (hint at IOConnect handles, offsets)
        unsigned iv=0; Ivar* ivs = class_copyIvarList(c,&iv);
        for (unsigned j=0;j<iv;j++) printf("    ivar %s : %s\n", ivar_getName(ivs[j]), ivar_getTypeEncoding(ivs[j])?:"");
        free(ivs);
    }
    free(names);
}

int main(void) {
    list("/System/Library/PrivateFrameworks/AppleDisplayTCONControl.framework/Versions/A/AppleDisplayTCONControl");
    return 0;
}
