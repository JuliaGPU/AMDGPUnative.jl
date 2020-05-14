# Quick Start

## Installation

After making sure that your ROCm stack is installed and working, simply add the required packages to your Julia environment:

```julia
]add HSARuntime, AMDGPUnative
```

If everything ran successfully, you can try loading the `AMDGPUnative` package and running the unit tests:

```julia
using AMDGPUnative
]test AMDGPUnative
```

!!! warning
    If you get an error message along the lines of `GLIB_CXX_... not found`, it's possible that the C++ runtime used to build the ROCm stack and the one used by Julia are different.
    If you built the ROCm stack yourself this is very likely the case since Julia normally ships with its own C++ runtime.
    For more information, check out this [GitHub issue](https://github.com/JuliaLang/julia/issues/34276).

    A quick fix is to use the `LD_PRELOAD` environment variable to make Julia use the system C++ runtime library, for example:

    ```sh
    LD_PRELOAD=/usr/lib/libstdc++.so julia
    ```

    Alternatively, you can build Julia from sources as described [here](https://github.com/JuliaLang/julia/blob/master/doc/build/build.md).

    You can quickly debug this issue by starting Julia and trying to load a ROCm library:

    ```julia
    using Libdl
    Libdl.dlopen("/opt/rocm/hsa/lib/libhsa-runtime64.so")
    ```

## Running a simple kernel

As a simple test, we will try to add two random vectors and make sure that the results from the CPU and the GPU are indeed the same.

We can start by first performing this simple calculation on the CPU:

```julia
N = 32
a = rand(Float64, N)
b = rand(Float64, N)
c_cpu = a + b
```

To do the same computation on the GPU, we first need to copy the two input arrays `a` and `b` to the device.
Toward that end, we will use the `HSAArray` type from `HSARuntime` to represent our GPU arrays.
We can create the two arrays by passing the host data to the constructor as follows:

```julia
using HSARuntime, AMDGPUnative
a_d = HSAArray(a)
b_d = HSAArray(b)
```

We need to create one additional array `c_d` to store the results:

```julia
c_d = similar(a_d)
```

!!! note
    `HSAArray` is a lightweight low-level array type, that does not support the GPUArrays.jl interface.
    Production code should instead use `ROCArray` once its ready, in a similar fashion to `CuArray`.

In this example, the postfix `_d` distinguishes a device memory object from its host memory counterpart.
This convention is completely arbitrary and you may name your device-side variables whatever you like; they are regular Julia variables.

Next, we will define the GPU kernel that does the actual computation:

```julia
function vadd!(c, a, b)
    i = workitemIdx().x
    c[i] = a[i] + b[i]
    return
end
```

This simple kernel starts by getting the current thread ID using [`workitemIdx`](@ref) and then performs the addition of the elements from `a` and `b`, storing the result in `c`.

Notice how we explicitly specify that this function does not return a value by adding the `return` statement.
This is necessary for all GPU kernels and we can enforce it by adding a `return`, `return nothing`, or even `nothing` at the end of the kernel.
If this statement is omitted, Julia will attempt to return the value of the last evaluated expression, in this case a `Float64`, which will cause a compilation failure as kernels cannot return values.

The easiest way to launch a GPU kernel is with the [`@roc`](@ref) macro, specifying that we want a single work group with `N` work items and calling it like an ordinary function:

```julia
@roc groupsize=N vadd!(c_d, a_d, b_d)
```

Keep in mind that kernel launches are asynchronous, meaning that you need to do some kind of synchronization before you use the result.
For instance, you can call `wait()` on the returned HSA signal value:

```julia
wait(@roc groupsize=N vadd!(c_d, a_d, b_d))
```

!!! warning "Naming conventions"
    Throughout this example we use terms like "work group" and "work item".
    These terms are used by the Khronos consortium and their APIs including OpenCL and Vulkan, as well as the HSA foundation.

    NVIDIA, on the other hand, uses some different terms in their CUDA API, which might be confusing to some users porting their kernels from CUDAnative to AMDGPUnative.
    As a quick summary, here is a mapping of the most common terms:
    
    | AMDGPUnative | CUDAnative |
    |:---:|:---:|
    | [`workitemIdx`](@ref) | [`threadIdx`](@ref) |
    | [`workgroupIdx`](@ref) | [`blockIdx`](@ref) |
    | [`workgroupDim`](@ref) | [`blockDim`](@ref) |
    | [`gridDim`](@ref) | No equivalent |
    | [`gridDimWG`](@ref) | `gridDim` |
    | `groupsize` | `threads` |
    | `gridsize` | `blocks * threads` |
    | `queue` | `stream` |

    For compatibilty reasons, the symbols in the CUDAnative column (except for `gridDim`) are also supported by AMDGPUnative.

Finally, we can make sure that the results match, by first copying the data to the host and then comparing it with the CPU results:

```julia
c = Array(c_d)

using Test
@test isapprox(c, c_cpu)
```

