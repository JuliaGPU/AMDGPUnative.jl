export dotrap, dodebugtrap

@inline dotrap() = ccall("llvm.trap", llvmcall, Cvoid, ())
@inline dodebugtrap() = ccall("llvm.debugtrap", llvmcall, Cvoid, ())

@warn "Remove me!"
@generated function myfakefunc()
    T_void = LLVM.VoidType(JuliaContext())
    T_pint8 = LLVM.PointerType(LLVM.Int8Type(JuliaContext()))
    T_i32 = LLVM.Int32Type(JuliaContext())

    # create function
    llvm_f, _ = create_function(T_i32)
    mod = LLVM.parent(llvm_f)

    # generate IR
    Builder(JuliaContext()) do builder
        entry = BasicBlock(llvm_f, "entry", JuliaContext())
        position!(builder, entry)
        gv = GV[]
        Core.println(string(gv))
        res = load!(builder, gv)
        ret!(builder, res)
    end

    call_function(llvm_f, Int32, Tuple{})
end
