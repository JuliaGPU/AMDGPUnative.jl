@generated function _intr(::Val{fname}, out_arg, inp_args...) where {fname,}
    inp_exprs = [:( inp_args[$i] ) for i in 1:length(inp_args)]
    inp_types = [inp_args...]
    out_type = convert(LLVMType, out_arg.parameters[1])

    # create function
    param_types = LLVMType[convert.(LLVMType, inp_types)...]
    llvm_f, _ = create_function(out_type, param_types)
    mod = LLVM.parent(llvm_f)

    # generate IR
    Builder(JuliaContext()) do builder
        entry = BasicBlock(llvm_f, "entry", JuliaContext())
        position!(builder, entry)

        # call the intrinsic
        intr_typ = LLVM.FunctionType(out_type, param_types)
        intr = LLVM.Function(mod, string(fname), intr_typ)
        value = call!(builder, intr, [parameters(llvm_f)...])
        ret!(builder, value)
    end

    call_function(llvm_f, out_arg.parameters[1], Tuple{inp_args...}, Expr(:tuple, inp_exprs...))
end

struct GCNIntrinsic
    jlname::Symbol
    rocname::Symbol
    isbroken::Bool # please don't laugh...
    isinverted::Bool
    # FIXME: Input/output types should have addrspaces
    inp_args::Tuple
    out_arg::Type
    roclib::Symbol
    suffix::Symbol
end

GCNIntrinsic(jlname, rocname=jlname; isbroken=false, isinverted=false,
             inp_args=(), out_arg=(), roclib=:ocml, suffix=fntypes[first(inp_args)]) =
    GCNIntrinsic(jlname, rocname, isbroken, isinverted, inp_args, out_arg, roclib, suffix)

function generate_intrinsic(intr)
    inp_vars = [gensym() for _ in 1:length(intr.inp_args)]
    inp_expr = [:($(inp_vars[idx])::$arg) for (idx,arg) in enumerate(intr.inp_args)]
    libname = Symbol("__$(intr.roclib)_$(intr.rocname)_$(intr.suffix)")
    @eval @inline function $(intr.jlname)($(inp_expr...))
        y = _intr($(Val(libname)), $(intr.out_arg), $(inp_expr...))
        return $(intr.isinverted ? :(1-y) : :y)
    end
end
