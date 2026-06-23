#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>
#import <stdio.h>
int main(void) {
    void* h = dlopen("/System/Library/PrivateFrameworks/AppleDisplayTCONControl.framework/AppleDisplayTCONControl", RTLD_NOW);
    FILE* f = fopen("/tmp/holder.pid","w"); fprintf(f,"%d\n",getpid()); fclose(f);
    fprintf(stderr,"holder pid=%d loaded=%p\n", getpid(), h);
    for(;;) pause();
    return 0;
}
