# compiler driver and main interface

# (::CompilerJob)
const compile_hook = Ref{Union{Nothing,Function}}(nothing)

"""
    compile(agent::HSAAgent, f, tt; kwargs...)

Compile a function `f` invoked with types `tt` for agent `agent`, returning
the compiled module and function, respectively of type `ROCModule` and
`ROCFunction`.

For a list of supported keyword arguments, refer to the documentation of
[`rocfunction`](@ref).
"""
compile(target::Symbol, agent::HSAAgent, @nospecialize(f::Core.Function),
                 @nospecialize(tt), kernel::Bool=true; libraries::Bool=true,
                 optimize::Bool=true,
                 strip::Bool=false, strict::Bool=true, kwargs...) =
            compile(target, CompilerJob(f, tt, agent, kernel; kwargs...);
                    libraries=libraries, 
                    optimize=optimize, strip=strip, strict=strict)
      

    AMDGPUnative.configured || error("AMDGPUnative.jl has not been configured; cannot JIT code.")

    job = CompilerJob(f, tt, agent, kernel; kwargs...)
    module_asm, module_entry = compile(job)

    # enable debug options based on Julia's debug setting
    jit_options = Dict{Any,Any}()
    roc_mod = ROCModule(module_asm, jit_options)
    roc_fun = ROCFunction(roc_mod, module_entry)

    return roc_mod, roc_fun
end

function compile(job::CompilerJob)
    if compile_hook[] != nothing
        hook = compile_hook[]
        compile_hook[] = nothing

        global globalUnique
        previous_globalUnique = globalUnique

        hook(job)

        globalUnique = previous_globalUnique
        compile_hook[] = hook
    end


    ## high-level code generation (Julia AST)

    @debug "(Re)compiling function" job

    check_method(job)


    ## low-level code generation (LLVM IR)

    mod, entry = irgen(job)

    need_library(lib) = any(f -> isdeclaration(f) &&
                                 intrinsic_id(f) == 0 &&
                                 haskey(functions(lib), LLVM.name(f)),
                            functions(mod))

    device_libs = load_device_libs(job.agent)
    for lib in device_libs
        if need_library(lib)
            link_device_lib!(job, mod, lib)
        end
    end
    link_oclc_defaults!(job, mod)

    # optimize the IR
    entry = optimize!(job, mod, entry)

    runtime = load_runtime(job.agent)
    if need_library(runtime)
        link_library!(job, mod, runtime)
    end

    prepare_execution!(job, mod)

    check_invocation(job, entry)

    # check generated IR
    check_ir(job, mod)
    verify(mod)

    ## machine code generation (GCN assembly)
    module_asm = mcgen(job, mod, entry)

    return module_asm, LLVM.name(entry)
end
