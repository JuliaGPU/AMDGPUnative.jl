const OCKL_INTRINSICS = GCNIntrinsic[]

#= TODO: Float16 Broken due to being i16 in Julia=#
for kind in (:wfred, :wfscan)
    for op in (:add, :max, :min)
        for jltype in (Float32, Float64, Int32, Int64, UInt32, UInt64)
            inp_args = kind == :wfscan ? (jltype,Bool) : (jltype,)
            push!(OCKL_INTRINSICS, GCNIntrinsic(Symbol(string(kind)*"_"*string(op)); roclib=:ockl, inp_args=inp_args, out_arg=jltype))
        end
    end
    for op in (:and, :or, :xor)
        for jltype in (Int32, Int64, UInt32, UInt64)
            inp_args = kind == :wfscan ? (jltype,Bool) : (jltype,)
            push!(OCKL_INTRINSICS, GCNIntrinsic(Symbol(string(kind)*"_"*string(op)); roclib=:ockl, inp_args=inp_args, out_arg=jltype))
        end
    end
end

generate_intrinsic.(OCKL_INTRINSICS)
