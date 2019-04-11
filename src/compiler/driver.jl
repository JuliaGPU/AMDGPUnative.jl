# compiler driver and main interface

# (::CompilerContext)
const compile_hook = Ref{Union{Nothing,Function}}(nothing)

"""
    compile(agent::HSAAgent, f, tt; kwargs...)

Compile a function `f` invoked with types `tt` for agent `agent`, returning
the compiled module and function, respectively of type `ROCModule` and
`ROCFunction`.

For a list of supported keyword arguments, refer to the documentation of
[`rocfunction`](@ref).
"""
function compile(agent::HSAAgent, @nospecialize(f::Core.Function), @nospecialize(tt);
                 kernel=true, kwargs...)
    AMDGPUnative.configured || error("AMDGPUnative.jl has not been configured; cannot JIT code.")

    ctx = CompilerContext(f, tt, agent, kernel; kwargs...)
    module_asm, module_entry = compile(ctx)

    # enable debug options based on Julia's debug setting
    jit_options = Dict{Any,Any}()
    roc_mod = ROCModule(module_asm, jit_options)
    roc_fun = ROCFunction(roc_mod, module_entry)

    return roc_mod, roc_fun
end

function compile(ctx::CompilerContext)
    if compile_hook[] != nothing
        hook = compile_hook[]
        compile_hook[] = nothing

        global globalUnique
        previous_globalUnique = globalUnique

        hook(ctx)

        globalUnique = previous_globalUnique
        compile_hook[] = hook
    end


    ## high-level code generation (Julia AST)

    @debug "(Re)compiling function" ctx

    check_method(ctx)


    ## low-level code generation (LLVM IR)

    mod, entry = irgen(ctx)

    need_library(lib) = any(f -> isdeclaration(f) &&
                                 intrinsic_id(f) == 0 &&
                                 haskey(functions(lib), LLVM.name(f)),
                            functions(mod))

    #= TODO
    libdevice = load_libdevice(ctx.agent)
    if need_library(libdevice)
        link_libdevice!(ctx, mod, libdevice)
    end
    =#

    # optimize the IR
    entry = optimize!(ctx, mod, entry)

    runtime = load_runtime(ctx.agent)
    if need_library(runtime)
        link_library!(ctx, mod, runtime)
    end
    #datalayout!(mod, "e-p:64:64-p1:64:64-p2:32:32-p3:32:32-p4:64:64-p5:32:32-p6:32:32-i64:64-v16:16-v24:32-v32:32-v48:64-v96:128-v192:256-v256:256-v512:512-v1024:1024-v2048:2048-n32:64-S32-A5")

    prepare_execution!(ctx, mod)

    check_invocation(ctx, entry)

    # check generated IR
    check_ir(ctx, mod)
    verify(mod)

    ## machine code generation (GCN assembly)
    module_asm = mcgen(ctx, mod, entry)

    return module_asm, LLVM.name(entry)
end
