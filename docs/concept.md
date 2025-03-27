# Zenith Kernel Concepts

This is an expanded copy of the original [Zenith Kernel Concept](https://pad.lassul.us/s/Kd6_LaiLa#) document.

## Features

- API compatibility via a Wayland inspired protocols interface
- Data tracing & tagging
- Namespaces
- Hashable kernel
- Signed executables
- Priviledged executables

## API Compatibility

Zenith emplores the concept of API compatibility inside the kernel. Many kernels require linking directly with
specific symbols. However, Zenith works by having consumers iterate the API's and bind to them.

### Example Prototype

```zig
const iter = ns.protocols.iterate();
while (iter.next()) |entry| {
  if (std.mem.eql(u8, entry.name, zenith.fs.API.name)) {
    const fs = ns.protocols.bind(entry, &zenith.fs.API, .{
      .version = .{
        .min = .{ .major = 0, .minor = 1, .patch = 0 },
        .max = .{ .major = 1, .minor = 0, .patch = 0 },
      },
    });
    defer fs.unbind();

    // Your code to interface with the filesystem API
  }
}
```

## Data Tracing

Zenith's security model assumes that any data outside the system it is running on cannot be trusted.
To do this, Zenith implements a tracing and tagging system which keep records of where data is going.

## Namespaces

To extend Zenith's security model, it implements a more complex form of chroots known as namespaces.
Namespaces are capable of fully sandboxing a single process or even multiple processes. It can prevent
fingerprinting of the host system by isolating the kernel API's. Every driver in the Zenith kernel runs
in its own namespace and gains access to various subsystems and hardware based on its metadata.

## Hashable Kernel

As Zenith knows what API's and modules are loaded in, it can generate a hash of the current "runtime"
configuration. This allows for verifying whether the kernel has been tampered with. A common use
case for this feature is to load the hash into a TPM's PCRs.

## Signed Executables

Executables which are trusted can be signed, this considered them to support the priviledged
executables environment.

## Priviledged Executables

Priviledged executables are executables which meets the system's trust caps. This allows for
accessing the kernel's APIs. However, accessing the priviledged environment requires the process
to start a new thread which gains the priviledged execution cap. With the cap, the thread
can hide itself from the rest of the user space and perform operations which usually require
root access.
