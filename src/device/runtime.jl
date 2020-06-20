# ROCm-specific runtime libraries


## GPU runtime library

# reset the runtime cache from global scope, so that any change triggers recompilation
GPUCompiler.reset_runtime()

# load or build the runtime for the most likely compilation job given a compute capability
function load_runtime(dev_isa::String)
    target = GCNCompilerTarget(; dev_isa=dev_isa)
    dummy_source = FunctionSpec(()->return, Tuple{})
    params = ROCCompilerParams()
    job = CompilerJob(target, dummy_source, params)
    GPUCompiler.load_runtime(job)
end

function signal_exception()
    flag_ptr = get_global_pointer(Val(:__global_exception_flag), Int64)
    Base.unsafe_store!(flag_ptr, 1)
    # TODO: threadfence_system()
    signal_completion(0)
    sendmsghalt(5) # stop wavefront generation
    sendmsghalt(6) # halt all running wavefronts
    # TODO: endpgm()
    return
end

function report_exception(ex)
    #= FIXME
    @rocprintf("""
        ERROR: a %s was thrown during kernel execution.
               Run Julia on debug level 2 for device stack traces.
        """, ex)
    =#
    @rocprint("""
        ERROR: an exception was thrown during kernel execution.
               Run Julia on debug level 2 for device stack traces.
        """)
    # TODO: Pass exception info and kernel ID to a global
    #=
    ring_ptr = get_global_pointer(Val(:__global_exception_ring), ExceptionEntry)
    ee = ExceptionEntry(_completion_signal(), C_NULL) # FIXME: DevicePtr(pointer(ex)))
    Base.unsafe_store!(ring_ptr, ee)
    =#
    return
end

# FIXME: report_oom(sz) = @rocprintf("ERROR: Out of dynamic GPU memory (trying to allocate %i bytes)\n", sz)
report_oom(sz) = @rocprintln("ERROR: Out of dynamic GPU memory")

function report_exception_name(ex)
    #= FIXME
    @rocprintf("""
        ERROR: a %s was thrown during kernel execution.
        Stacktrace:
        """, ex)
    =#
    @rocprint("""
        ERROR: an exception was thrown during kernel execution.
        Stacktrace:
        """)
    return
end

function report_exception_frame(idx, func, file, line)
    # FIXME: @rocprintf(" [%i] %s at %s:%i\n", idx, func, file, line)
    #@rocprintln(" [%i] %s at %s:%i")
    return
end


## ROCm device library

const libcache = Dict{String, LLVM.Module}()

function load_device_libs(dev_isa)
    device_libs_path === nothing && return

    isa_short = replace(dev_isa, "gfx"=>"")
    device_libs = LLVM.Module[]
    bitcode_files = (
        "hc.amdgcn.bc",
        "hip.amdgcn.bc",
        "irif.amdgcn.bc",
        "ockl.amdgcn.bc",
        "oclc_isa_version_$isa_short.amdgcn.bc",
        "opencl.amdgcn.bc",
        "ocml.amdgcn.bc",
    )

    for file in bitcode_files
        ispath(joinpath(device_libs_path, file)) || continue
        name, ext = splitext(file)
        lib = get!(libcache, name) do
            file_path = joinpath(device_libs_path, file)
            open(file_path) do io
                parse(LLVM.Module, read(file_path), JuliaContext())
            end
        end
        push!(device_libs, lib)
    end

    @assert !isempty(device_libs) "No device libs detected!"
    return device_libs
end

function link_device_libs!(mod::LLVM.Module, dev_isa::String, undefined_fns)
    libs::Vector{LLVM.Module} = load_device_libs(dev_isa)

    ufns = undefined_fns
    # TODO: only link if used
    # TODO: make these globally/locally configurable
    link_oclc_defaults!(mod, dev_isa)
    for lib in libs
        # override libdevice's triple and datalayout to avoid warnings
        triple!(lib, triple(mod))
        datalayout!(lib, datalayout(mod))
    end

    GPUCompiler.link_library!(mod, libs)
end

function link_oclc_defaults!(mod::LLVM.Module, dev_isa::String; finite_only=false,
                             unsafe_math=false, correctly_rounded_sqrt=true, daz=false)
    # link in some defaults for OCLC knobs, to prevent undefined variable errors
    lib = LLVM.Module("OCLC")
    triple!(lib, triple(mod))
    datalayout!(lib, datalayout(mod))

    isa_short = replace(dev_isa, "gfx"=>"")
    for (name,value) in (
            "__oclc_ISA_version"=>parse(Int32, isa_short),
            "__oclc_finite_only_opt"=>Int32(finite_only),
            "__oclc_unsafe_math_opt"=>Int32(unsafe_math),
            "__oclc_correctly_rounded_sqrt32"=>Int32(correctly_rounded_sqrt),
            "__oclc_daz_opt"=>Int32(daz))
        gvtype = convert(LLVMType, typeof(value))
        gv = GlobalVariable(lib, gvtype, name, 4)
        init = ConstantInt(Int32(0), JuliaContext())
        initializer!(gv, init)
        unnamed_addr!(gv, true)
        constant!(gv, true)
    end

    link!(mod, lib)
end
