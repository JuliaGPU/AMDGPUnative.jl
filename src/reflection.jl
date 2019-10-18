# code reflection entry-points

using InteractiveUtils


#
# code_* replacements
#

# NOTE: these functions replicate parts of the main compiler driver in order to generate
#       more compact code (i.e. without the run-time library) and/or to support generating
#       otherwise invalid code (e.g. with missing symbols).

"""
    code_llvm([io], f, types; optimize=true, cap::VersionNumber, kernel=true,
                              dump_module=false, strip_ir_metadata=true)

Prints the device LLVM IR generated for the method matching the given generic function and
type signature to `io` which defaults to `stdout`. The IR is optimized according to
`optimize` (defaults to true), which includes entry-point specific optimizations if `kernel`
is set (defaults to false). The device capability `cap` to generate code for defaults to the
current active device's capability, or v"2.0" if there is no such active context. The entire
module, including headers and other functions, is dumped if `dump_module` is set (defaults
to false). Finally, setting `strip_ir_metadata` removes all debug metadata (defaults to
true).

See also: [`@device_code_llvm`](@ref), [`InteractiveUtils.code_llvm`](@ref)
"""
function code_llvm(io::IO, @nospecialize(func::Core.Function), @nospecialize(types=Tuple);
                   optimize::Bool=true, agent::HSAAgent=get_default_agent(),
                   dump_module::Bool=false, strip_ir_metadata::Bool=true,
                   kernel::Bool=false, kwargs...)
    tt = Base.to_tuple_type(types)
    job = CompilerJob(func, tt, agent, kernel; kwargs...)
    code_llvm(io, job; optimize=optimize, dump_module=dump_module,
              strip_ir_metadata=strip_ir_metadata)
end
function code_llvm(io::IO, job::CompilerJob; optimize::Bool=true,
                   dump_module::Bool=false, strip_ir_metadata::Bool=true)
    check_method(job)
    mod, entry = irgen(job)
    if optimize
        entry = optimize!(job, mod, entry)
    end
    if strip_ir_metadata
        strip_debuginfo!(mod)
    end
    if dump_module
        show(io, mod)
    else
        show(io, entry)
    end
end
code_llvm(@nospecialize(func), @nospecialize(types=Tuple); kwargs...) =
    code_llvm(stdout, func, types; kwargs...)

"""
    code_gcn([io], f, types; cap::VersionNumber, kernel=false, strip_ir_metadata=true)

Prints the GCN assembly generated for the method matching the given generic function and
type signature to `io` which defaults to `stdout`. The device capability `cap` to generate
code for defaults to the current active device's capability, or v"2.0" if there is no such
active context. The optional `kernel` parameter indicates whether the function in question
is an entry-point function, or a regular device function. Finally, setting
`strip_ir_metadata` removes all debug metadata (defaults to true).

See also: [`@device_code_gcn`](@ref)
"""
function code_gcn(io::IO, @nospecialize(func::Core.Function), @nospecialize(types=Tuple);
                  agent::HSAAgent=get_default_agent(), kernel::Bool=false,
                  strip_ir_metadata::Bool=true, kwargs...)
    tt = Base.to_tuple_type(types)
    job = CompilerJob(func, tt, agent, kernel; kwargs...)
    code_gcn(io, job; strip_ir_metadata=strip_ir_metadata)
end
function code_gcn(io::IO, job::CompilerJob; strip_ir_metadata::Bool=true)
    check_method(job)
    mod, entry = irgen(job)
    entry = optimize!(job, mod, entry)
    if strip_ir_metadata
        strip_debuginfo!(mod)
    end
    prepare_execution!(job, mod)
    gcn = mcgen(job, mod, entry; file_type=LLVM.API.LLVMAssemblyFile)
    print(io, String(gcn))
end
code_gcn(@nospecialize(func), @nospecialize(types=Tuple); kwargs...) =
    code_gcn(stdout, func, types; kwargs...)

#
# @device_code_* functions
#

export @device_code_lowered, @device_code_typed, @device_code_warntype,
       @device_code_llvm, @device_code_gcn, @device_code_sass,
       @device_code

function emit_hooked_compilation(inner_hook, ex...)
    user_code = ex[end]
    user_kwargs = ex[1:end-1]
    quote
        # wipe the compile cache to force recompilation
        empty!(AMDGPUnative.compilecache)

        local kernels = 0
        function outer_hook(job)
            kernels += 1
            $inner_hook(job; $(map(esc, user_kwargs)...))
        end

        if AMDGPUnative.compile_hook[] != nothing
            error("Chaining multiple @device_code calls is unsupported")
        end
        try
            AMDGPUnative.compile_hook[] = outer_hook
            $(esc(user_code))
        finally
            AMDGPUnative.compile_hook[] = nothing
        end

        if kernels == 0
            error("no kernels executed while evaluating the given expression")
        end

        nothing
    end
end

# NOTE: these hooks take both a `f` and an inner `f`, because of how `@roc` works:
#       kernels are automatically wrapper in a function returning nothing, for usability.
#
#       Julia-level reflection (lowered/typed/warntype) skips these wrapper, because we
#       can't do call-site inlining and the kernel wrapper would hide any meaningful code.
#
#       at the LLVM level, we inline everything so there's no need to hide the wrapper.

"""
    @device_code_lowered ex

Evaluates the expression `ex` and returns the result of
[`InteractiveUtils.code_lowered`](@ref) for every compiled GCN kernel.

See also: [`InteractiveUtils.@code_lowered`](@ref)
"""
macro device_code_lowered(ex...)
    quote
        buf = Any[]
        function hook(job::CompilerJob)
            append!(buf, code_lowered(job.f, job.tt))
        end
        $(emit_hooked_compilation(:hook, ex...))
        buf
    end
end

"""
    @device_code_typed ex

Evaluates the expression `ex` and returns the result of
[`InteractiveUtils.code_typed`](@ref) for every compiled GCN kernel.

See also: [`InteractiveUtils.@code_typed`](@ref)
"""
macro device_code_typed(ex...)
    quote
        buf = Any[]
        function hook(job::CompilerJob)
            if VERSION >= v"1.1.0"
                append!(buf, code_typed(job.f, job.tt, debuginfo=:source))
            else
            append!(buf, code_typed(job.f, job.tt))
            end
        end
        $(emit_hooked_compilation(:hook, ex...))
        buf
    end
end

"""
    @device_code_warntype [io::IO=stdout] ex

Evaluates the expression `ex` and prints the result of
[`InteractiveUtils.code_warntype`](@ref) to `io` for every compiled GCN kernel.

See also: [`InteractiveUtils.@code_warntype`](@ref)
"""
macro device_code_warntype(ex...)
    function hook(job::CompilerJob; io::IO=stdout, kwargs...)
        code_warntype(io, job.f, job.tt; kwargs...)
    end
    emit_hooked_compilation(hook, ex...)
end

"""
    @device_code_llvm [io::IO=stdout, ...] ex

Evaluates the expression `ex` and prints the result of [`InteractiveUtils.code_llvm`](@ref)
to `io` for every compiled GCN kernel. For other supported keywords, see
[`AMDGPUnative.code_llvm`](@ref).

See also: [`InteractiveUtils.@code_llvm`](@ref)
"""
macro device_code_llvm(ex...)
    hook(job::CompilerJob; io::IO=stdout, kwargs...) = code_llvm(io, job; kwargs...)
    emit_hooked_compilation(hook, ex...)
end

"""
    @device_code_gcn [io::IO=stdout, ...] ex

Evaluates the expression `ex` and prints the result of [`AMDGPUnative.code_gcn`](@ref) to `io`
for every compiled GCN kernel. For other supported keywords, see
[`AMDGPUnative.code_gcn`](@ref).
"""
macro device_code_gcn(ex...)
    hook(job::CompilerJob; io::IO=stdout, kwargs...) = code_gcn(io, job; kwargs...)
    emit_hooked_compilation(hook, ex...)
end

"""
    @device_code dir::AbstractString=... [...] ex

Evaluates the expression `ex` and dumps all intermediate forms of code to the directory
`dir`.
"""
macro device_code(ex...)
    only(xs) = (@assert length(xs) == 1; first(xs))
    function hook(job::CompilerJob; dir::AbstractString)
        name = something(job.name, nameof(job.f))
        fn = "$(name)_$(globalUnique+1)" 
        mkpath(dir)

        open(joinpath(dir, "$fn.lowered.jl"), "w") do io
            code = only(code_lowered(job.f, job.tt))
            println(io, code)
        end

        open(joinpath(dir, "$fn.typed.jl"), "w") do io
                    if VERSION >= v"1.1.0"
                code = only(code_typed(job.f, job.tt, debuginfo=:source))
            else
            code = only(code_typed(job.f, job.tt))
            end
            println(io, code)
        end
        # strip_ir_metadata vs. raw=true ?? -WSP    
        open(joinpath(dir, "$fn.unopt.ll"), "w") do io
            code_llvm(io, job; dump_module=true, strip_ir_metadata=false, optimize=false)
        end

        open(joinpath(dir, "$fn.opt.ll"), "w") do io
            code_llvm(io, job; dump_module=true, strip_ir_metadata=false)
        end

        open(joinpath(dir, "$fn.gcn"), "w") do io
            code_gcn(io, job)
        end
    end
    emit_hooked_compilation(hook, ex...)
end
