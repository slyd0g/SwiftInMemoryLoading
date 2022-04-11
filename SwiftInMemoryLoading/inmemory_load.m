//
//  inmemory_load.m
//  SwiftInMemoryLoading
//
//  Created by Justin Bui on 3/9/22.
//

#import <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <stdio.h>

void executeMemory(void* memory, int machoSize, const char* functionName, int argumentCount, char** arguments) {
    NSObjectFileImage fileImage = NULL;
    NSModule module = NULL;
    NSSymbol symbol = NULL;
    int pid = 0;

    *((uint8_t*)memory + 12) =  MH_BUNDLE;
    
    NSCreateObjectFileImageFromMemory(memory, machoSize, &fileImage);
    if(fileImage == NULL){
            //printf("     |-> Failed to create File Image from memory\n");
    }
    else {
        //printf("     |-> NSCreateObjectFileImageFromMemory success!\n");
    }
    
    module = NSLinkModule(fileImage, "module", NSLINKMODULE_OPTION_NONE);
    if(module == NULL){
        //printf("     |-> Failed to get module from File Image\n");
    }
    else {
        //printf("     |-> NSLinkModule success!\n");
    }
    
    symbol = NSLookupSymbolInModule(module, functionName);
    if(symbol == NULL){
        //printf("     |-> Failed to find function name in module\n");
    }
    else {
        //printf("     |-> NSLookupSymbolInModule success!\n");
        //printf("     |-> Executing function pointer!\n");
        //printf("     |-> Mach-O Output:\n");
    }
    
    int(*main)(int, char**) = (int(*)(int, char**)) NSAddressOfSymbol(symbol);

    main(argumentCount, arguments);
    
    //printf("    |-> Cleaning up with NSUnLinkModule and NSDestroyObjectFileImage\n");
    NSUnLinkModule(module, NSUNLINKMODULE_OPTION_NONE);
    NSDestroyObjectFileImage(fileImage);
}
