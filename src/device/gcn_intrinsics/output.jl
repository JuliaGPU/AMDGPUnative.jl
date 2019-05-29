# Formatted Output (B.17)

export @rocprintf

@generated function promote_c_argument(arg)
    # > When a function with a variable-length argument list is called, the variable
    # > arguments are passed using C's old ``default argument promotions.'' These say that
    # > types char and short int are automatically promoted to int, and type float is
    # > automatically promoted to double. Therefore, varargs functions will never receive
    # > arguments of type char, short int, or float.

    if arg == Cchar || arg == Cshort
        return :(Cint(arg))
    elseif arg == Cfloat
        return :(Cdouble(arg))
    else
        return :(arg)
    end
end

"""
Print a formatted string in device context on the host standard output:

    @rocprintf("%Fmt", args...)

Note that this is not a fully C-compliant `printf` implementation; see the CUDA
documentation for supported options and inputs.

Also beware that it is an untyped, and unforgiving `printf` implementation. Type widths need
to match, eg. printing a 64-bit Julia integer requires the `%ld` formatting string.
"""
macro rocprintf(fmt::String, args...)
    fmt_val = Val(Symbol(fmt))

    return :(_rocprintf($fmt_val, $(map(arg -> :(promote_c_argument($arg)), esc.(args))...)))
end

@generated function _rocprintf(::Val{fmt}, argspec...) where {fmt}
    arg_exprs = [:( argspec[$i] ) for i in 1:length(argspec)]
    arg_types = [argspec...]

    T_void = LLVM.VoidType(JuliaContext())
    T_int32 = LLVM.Int32Type(JuliaContext())
    T_pint8 = LLVM.PointerType(LLVM.Int8Type(JuliaContext()))
    streltyp = convert(LLVMType, Int8)

    # create functions
    param_types = LLVMType[convert.(LLVMType, arg_types)...]
    llvm_f, _ = create_function(T_int32, param_types)
    mod = LLVM.parent(llvm_f)

    # generate IR
    Builder(JuliaContext()) do builder
        entry = BasicBlock(llvm_f, "entry", JuliaContext())
        position!(builder, entry)

        Core.println("\e[32mBegin!\e[0m")
        # g = @0 = private unnamed_addr constant [8 x i8] c"Hello!\0A\00"
        #str = globalstring_ptr!(builder, String(fmt))
        gvtype = LLVM.ArrayType(streltyp, length(string(fmt)))
        str = GlobalVariable(mod, gvtype, "myprintfstr", 4)
        #init = ConstantInt(Int32(0), JuliaContext())
        # FIXME: Initialize to string value
        init = null(gvtype)
        initializer!(str, init)
        unnamed_addr!(str, true)
        constant!(str, true)
        #Core.println(unsafe_string(LLVM.API.LLVMPrintValueToString(LLVM.ref(str))))
        Core.println("\e[32mEnd!\e[0m")

        # construct and fill args buffer
        if isempty(argspec)
            buffer = LLVM.PointerNull(T_pint8)
        else
            argtypes = LLVM.StructType("printf_args", JuliaContext())
            elements!(argtypes, param_types)

            args = alloca!(builder, argtypes)
            for (i, param) in enumerate(parameters(llvm_f))
                p = struct_gep!(builder, args, i-1)
                store!(builder, param, p)
            end

            buffer = bitcast!(builder, args, T_pint8)
        end

        # invoke vprintf and return
        Core.println("\e[32mStart 2!\e[0m")
        vprintf_typ = LLVM.FunctionType(T_int32, [T_pint8, T_pint8])
        vprintf = LLVM.Function(mod, "vprintf", vprintf_typ)
        Core.println("\e[32mMiddle 2.1!\e[0m")
        Core.println(unsafe_string(LLVM.API.LLVMPrintValueToString(LLVM.ref(vprintf))))
        _str = inbounds_gep!(builder, str, [ConstantInt(0, JuliaContext()), ConstantInt(0, JuliaContext())])
        __str = addrspacecast!(builder, _str, LLVM.PointerType(LLVM.Int8Type(JuliaContext())))
        Core.println(unsafe_string(LLVM.API.LLVMPrintValueToString(LLVM.ref(__str))))
        Core.println(unsafe_string(LLVM.API.LLVMPrintValueToString(LLVM.ref(buffer))))
        Core.println("\e[32mMiddle 2.2!\e[0m")
        #_str = bitcast!(builder, str, T_pint8)
        chars = call!(builder, vprintf, [__str, buffer])
        Core.println("\e[32mEnd 2!\e[0m")

        ret!(builder, chars)
    end

    arg_tuple = Expr(:tuple, arg_exprs...)
    call_function(llvm_f, Int32, Tuple{arg_types...}, arg_tuple)
end
