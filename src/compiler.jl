struct ROCCompilerParams <: AbstractCompilerParams end

ROCCompilerJob = CompilerJob{GCNCompilerTarget,ROCCompilerParams}

GPUCompiler.runtime_module(::ROCCompilerJob) = AMDGPUnative

# filter out functions from device libs
GPUCompiler.isintrinsic(job::ROCCompilerJob, fn::String) =
    invoke(GPUCompiler.isintrinsic,
           Tuple{CompilerJob{GCNCompilerTarget}, typeof(fn)},
           job, fn) ||
    startswith(fn, "rocm")

function GPUCompiler.process_module!(job::ROCCompilerJob, mod::LLVM.Module)
    invoke(GPUCompiler.process_module!,
           Tuple{CompilerJob{GCNCompilerTarget}, typeof(mod)},
           job, mod)
    # Run this early (before optimization) to ensure we link OCKL
    emit_exception_user!(mod)
end
function GPUCompiler.finish_module!(job::ROCCompilerJob, mod::LLVM.Module)
    invoke(GPUCompiler.finish_module!,
           Tuple{CompilerJob{GCNCompilerTarget}, typeof(mod)},
           job, mod)
    delete_exception_user!(mod)
end

function GPUCompiler.link_libraries!(job::ROCCompilerJob, mod::LLVM.Module,
                                     undefined_fns::Vector{String})
    invoke(GPUCompiler.link_libraries!,
           Tuple{CompilerJob{GCNCompilerTarget}, typeof(mod), typeof(undefined_fns)},
           job, mod, undefined_fns)

    link_device_libs!(mod, job.target.dev_isa, undefined_fns)
end
