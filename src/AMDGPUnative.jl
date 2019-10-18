module AMDGPUnative

using LLVM, LLVM.Interop
using InteractiveUtils
using HSARuntime
using Adapt
using TimerOutputs
using DataStructures
using Libdl

#= should definitely have the equivalent of this since LLVM versions so critical for AMDGPU
verlist(vers) = join(map(ver->"$(ver.major).$(ver.minor)", sort(collect(vers))), ", ", " and ")

function llvm_support(version)
    @debug("Using LLVM v$version")

    # https://github.com/JuliaGPU/CUDAnative.jl/issues/428
    if version >= v"8.0" && VERSION < v"1.3.0-DEV.547"
        error("LLVM 8.0 requires a newer version of Julia")
    end

    InitializeAllTargets()
    haskey(targets(), "nvptx") ||
        error("""
            Your LLVM does not support the NVPTX back-end.

            This is very strange; both the official binaries
            and an unmodified build should contain this back-end.""")

    target_support = sort(collect(CUDAapi.devices_for_llvm(version)))

    ptx_support = CUDAapi.isas_for_llvm(version)
    push!(ptx_support, v"6.0") # JuliaLang/julia#23817
    ptx_support = sort(collect(ptx_support))

    @debug("LLVM supports devices $(verlist(target_support)); PTX $(verlist(ptx_support))")
    return target_support, ptx_support
end
let
    # LLVM.jl

    llvm_version = LLVM.version()
    llvm_targets, llvm_isas = llvm_support(llvm_version)


    # Julia

    julia_llvm_version = Base.libllvm_version
    if julia_llvm_version != llvm_version
        error("LLVM $llvm_version incompatible with Julia's LLVM $julia_llvm_version")
    end
end
=#
const configured = HSARuntime.configured

# where the ROCm-Device-Libs bitcode goes
include(joinpath(@__DIR__, "..", "deps", "deps.jl"))
const device_libs_path = joinpath(@__DIR__, "..", "deps", "usr", "lib")

# needs to be loaded _before_ the compiler infrastructure, because of generated functions
include(joinpath("device", "tools.jl"))
include(joinpath("device", "pointer.jl"))
include(joinpath("device", "array.jl"))
include(joinpath("device", "gcn.jl"))
include(joinpath("device", "runtime.jl"))

include("execution_utils.jl")
include("compiler.jl")
include("execution.jl")

include("reflection.jl")

function __init__()
    check_deps()
end

end # module
