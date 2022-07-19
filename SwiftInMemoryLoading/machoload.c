//
//  machoload.c
//  SwiftInMemoryLoading
//
//  Created by Justin Bui on 3/11/22.
//

/*
 ================================================================================
 modified from this: https://github.com/its-a-feature/macos_execute_from_memory (supports only bundle)
 code injection: https://github.com/CylanceVulnResearch/osx_runbin by Stephanie Archibald (does not support m1 x64 emulation and FAT header)
 FAT header (universal Macho) parsing: @exploitpreacher
 atexit() to prevent Mach-O from exiting + searching for Mach-O header with NSLookupSymbolInModule: https://github.com/djhohnstein/macos_shell_memory
 ================================================================================
 */

#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h> // for close

#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include <sys/types.h>
#include <mach-o/fat.h>
#include <setjmp.h>

// Stack info for when dynamically loaded program exits
static jmp_buf SAVED_ENV;
// Integer switch for program control flow on setjmp
static int RETVAL = 0;

void my_exit() {
    if (RETVAL == 0) {
        longjmp(SAVED_ENV, 1);
    } else {
        return;
    }
}

int find_epc(unsigned long base, struct entry_point_command **entry) {
    // find the entry point command by searching through base's load commands
    struct mach_header_64 *mh;
    struct load_command *lc;
    
    *entry = NULL;
    mh = (struct mach_header_64 *)base;
    lc = (struct load_command *)(base + sizeof(struct mach_header_64));
    for(int i=0; i<mh->ncmds; i++) {
        if(lc->cmd == LC_MAIN) {    //0x80000028
            *entry = (struct entry_point_command *)lc;
            return 0;
        }
        lc = (struct load_command *)((unsigned long)lc + lc->cmdsize);
    }
    return 1;
}
uint32_t swap_endian(uint32_t wrong_endian) {
    uint32_t swapped = ((wrong_endian>>24)&0xff) | // move byte 3 to byte 0
    ((wrong_endian<<8)&0xff0000) | // move byte 1 to byte 2
    ((wrong_endian>>8)&0xff00) | // move byte 2 to byte 1
    ((wrong_endian<<24)&0xff000000); // byte 0 to byte 3
    return swapped;
}

void executeMemory2(void* memory, int machoSize, const char* functionName, int argumentCount, char** arguments, int monterey)
{
    NSObjectFileImage fileImage = NULL;
    NSModule module = NULL;
    NSSymbol symbol = NULL;
    void *codeAddr = memory;
    void *machoAddr = NULL;
    uint32_t type;
    uint32_t offset = 0;
    uint32_t machoBufSize;
    
    // determine the type of the file we loaded
    if (((int *)codeAddr)[0] == 0xbebafeca) /* MAGIC for FAT */ {
        struct fat_arch *fa;
        uint32_t num_arch = swap_endian(((uint32_t *)codeAddr)[1]);
        
        for (int i=0;i<num_arch;i++) {
            fa = (struct fat_arch *)(codeAddr + (sizeof(uint32_t) * 2) + ((sizeof (struct fat_arch))*i));
            offset = swap_endian(fa->offset);
            machoAddr = codeAddr + offset;
            if (((int *)codeAddr)[0] != 0xfeedfacf /* MAGIC for MACHO 64 */) {
                break;
            }
        }
        if (!machoAddr) {
            goto err;
        }
    } else if (((int *)codeAddr)[0] == 0xfeedfacf) /* MAGIC for MACHO x64 */ {
        machoAddr = codeAddr;
    } else {
        goto err;
    }
    
    type = ((int *)machoAddr)[3];
    machoBufSize = machoSize - offset;
    
    if (type == 0x8) { // bundle - nothing to do
        void (*function)();
        
        NSCreateObjectFileImageFromMemory(machoAddr, machoBufSize, &fileImage);
        module = NSLinkModule(fileImage, "module", NSLINKMODULE_OPTION_NONE);
        
        symbol = NSLookupSymbolInModule(module, "_main");
        function = NSAddressOfSymbol(symbol);
        RETVAL = setjmp(SAVED_ENV);
        if (RETVAL == 0) {
            // Create an atexit routine to longjmp back to our saved buffer.
            // When the thin MachO executes in-memory, it'll attempt to exit
            // the program. Creating this thin hook allows us to stop that process.
            atexit(my_exit);
            function();
        }
    } else { // we have to find the main function
        struct entry_point_command *epc;
        
        ((int *)machoAddr)[3] = 0x8; // first change to mh_bundle type
        
        NSCreateObjectFileImageFromMemory(machoAddr, machoBufSize, &fileImage);
        module = NSLinkModule(fileImage, "module", NSLINKMODULE_OPTION_NONE);
        if (monterey == 1) {
            //module = ((uintptr_t)(module)) >> 1;
        }

        NSSymbol symbol = NSLookupSymbolInModule(module, "__mh_execute_header");
        void* execute_base = NSAddressOfSymbol(symbol);
        
        
        if(find_epc(execute_base, &epc)) {
            goto err;
        }
        
        int(*main)(int, char**, char**, char**) = (int(*)(int, char**, char**, char**))(execute_base + epc->entryoff);
        char *env[] = {NULL};
        char *apple[] = {NULL};
        
        RETVAL = setjmp(SAVED_ENV);
        if (RETVAL == 0) {
            // Create an atexit routine to longjmp back to our saved buffer.
            // When the thin MachO executes in-memory, it'll attempt to exit
            // the program. Creating this thin hook allows us to stop that process.
            atexit(my_exit);
            main(argumentCount, arguments, env, apple);
        }
    }
err:
    NSUnLinkModule(module, NSUNLINKMODULE_OPTION_NONE);
    NSDestroyObjectFileImage(fileImage);
}
