# support for device-side exceptions (from CUDAnative/src/exceptions.jl)

## exception type

struct KernelException <: Exception
    dev::RuntimeDevice
end

function Base.showerror(io::IO, err::KernelException)
    print(io, "KernelException: exception thrown during kernel execution on device $(err.dev.device)")
end

## exception ring buffer

struct ExceptionEntry
    kern_id::UInt64
    ptr::DevicePtr{Any,AS.Global}
end
ExceptionEntry() = ExceptionEntry(0, DevicePtr{Any,AS.Global}(0))

## exception codegen

# emit a global variable for storing the current exception status
function emit_exception_flag!(mod::LLVM.Module)
    # add the global variable
    gbl_name = "__global_exception_flag"
    if !haskey(LLVM.globals(mod), gbl_name)
        T_ptr = convert(LLVMType, Ptr{Int64})
        gv = GlobalVariable(mod, T_ptr, gbl_name)
        #initializer!(gv, LLVM.ConstantInt(T_ptr, 0))
        linkage!(gv, LLVM.API.LLVMExternalLinkage)
        extinit!(gv, true)
        set_used!(mod, gv)
    end

    # add a fake user for __ockl_hsa_signal_store
    if !haskey(LLVM.functions(mod), "__fake_global_exception_flag_user")
        ctx = JuliaContext()
        ft = LLVM.FunctionType(LLVM.VoidType(ctx))
        fn = LLVM.Function(mod, "__fake_global_exception_flag_user", ft)
        Builder(ctx) do builder
            entry = BasicBlock(fn, "entry")
            position!(builder, entry)
            T_nothing = LLVM.VoidType(ctx)
            T_i32 = LLVM.Int32Type(ctx)
            T_i64 = LLVM.Int64Type(ctx)
            T_signal_store = LLVM.FunctionType(T_nothing, [T_i64, T_i64, T_i32])
            signal_store = LLVM.Function(mod, "__ockl_hsa_signal_store", T_signal_store)
            call!(builder, signal_store, [ConstantInt(0,ctx),
                                          ConstantInt(0,ctx),
                                          # __ATOMIC_RELEASE == 3
                                          ConstantInt(Int32(3), JuliaContext())])
            ret!(builder)
        end
    end
end
