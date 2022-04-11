//
//  main.swift
//  SwiftInMemoryLoading
//
//  Created by Justin Bui on 3/9/22.
//

import Foundation

let pipeName = "/private/tmp/" + UUID().uuidString
let functionName = "_main"
var cargs:Array<Optional<UnsafeMutablePointer<Int8>>> = []

func startPipeServer() {
    // Delete named pipe if it exists
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: pipeName) {
        do {
            try FileManager.default.removeItem(atPath: pipeName)
        }
        catch {
            print("Exception caught: \(error)")
        }
    }

    // Create named pipe
    let namedPipe = mkfifo(pipeName, S_IFIFO|S_IRUSR|S_IWUSR)
    if namedPipe != 0 {
        print("[-] Could not created named pipe. Error:", errno)
        exit(-1)
    }
    else {
        print("[+] Named pipe created successfully at", pipeName)
    }

    let charBufferSize = 10000
    var charBuffer = [Int8](repeating:0, count:charBufferSize)
    while(true) {
        // Open named pipe for reading (this is blocking until a client connects for writing)
        print("[+] Waiting for a client to write ...")
        let fileDescriptor = open(pipeName, O_RDONLY)
        if fileDescriptor == -1 {
            print("[-] Could not open named pipe. Error:", errno)
            exit(-1)
        }

        // Read data from named pipe
        let readPipe = read(fileDescriptor, &charBuffer, charBufferSize)
        if readPipe == -1 {
            print("[-] Could not read data from named pipe. Error:", errno)
            
            // Delete named pipe
            do {
                try FileManager.default.removeItem(atPath: pipeName)
            }
            catch {
                print("Exception caught: \(error)")
            }
        }
        else {
            print("[+] Grabbed file handle to named pipe")
            print("[+] Read data from the pipe")
            print("     |-> Data:\n\n\(String(cString: charBuffer))")
            
            if (String(cString:charBuffer).contains("WRITE_COMPLETE"))
            {
                // Delete named pipe
                do {
                    try FileManager.default.removeItem(atPath: pipeName)
                }
                catch {
                    print("Exception caught: \(error)")
                }

                // Close file descriptor
                close(fileDescriptor)
                return
            }
        }
    }
}

func executeMemorySwift(macho: Data, arguments: [String]) {
    let machoSize = macho.count

    if machoSize < 1 {
        exit(-1)
    }

    let rawPtrMacho = UnsafeMutableRawPointer.init(mutating: (macho as NSData).bytes)
    executeMemory2(rawPtrMacho, Int32(machoSize), functionName, Int32(arguments.count), &cargs, CheckMonterey())
}

func CheckMonterey() -> Int32 {
    var osVersion = OperatingSystemVersion.init()
    osVersion.majorVersion = 12 //Monterey
    if(ProcessInfo.processInfo.isOperatingSystemAtLeast(osVersion)) {
        return 1
    }
    else {
        return 0
    }
}

func Help() {
    print("|---------------------------------------------|")
    print("|-----| SwiftInMemoryLoading by @slyd0g |-----|")
    print("|---------------------------------------------|")
    print("./SwiftInMemoryLoading </full/path/to/binary> <arguments>")
}

var cliArguments = CommandLine.arguments
if cliArguments.count == 1
{
    Help()
    exit(0)
}
else if cliArguments.count >= 2 {
    // Load up Mach-O
    let macho = try Data(contentsOf: URL(fileURLWithPath: cliArguments[1]))

    // Load up CLI arguments if they exist
    if cliArguments.count > 2 {
        cliArguments = Array(cliArguments.dropFirst(1))
    }
    cargs = cliArguments.map { strdup($0) }

    // Setup DispatchQueue to run async threads
    let queue = DispatchQueue(label: "", qos: .background, attributes: .concurrent)

    // Start pipe server in a thread
    queue.async{startPipeServer()}
    sleep(1)

    // Save stdout/stderr
    let saveStdout = dup(1)
    let saveStderr = dup(2)
    freopen(pipeName, "w", stdout)
    freopen(pipeName, "w", stderr)

    // Execute Mach-O in memory
    executeMemorySwift(macho: macho, arguments: cliArguments)

    // Flush stdout to push it to the named pipe + restore old stdout/stderr, no need to do this for stderr because it is streamed
    print("WRITE_COMPLETE")
    sleep(2)
    fflush(stdout)
    sleep(2)
    dup2(saveStdout, 1)
    dup2(saveStderr, 2)

    // Free the duplicated strings
    for ptr in cargs { free(ptr) }

    exit(42)
}
