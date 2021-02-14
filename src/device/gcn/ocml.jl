const OCML_INTRINSICS = GCNIntrinsic[]

for jltype in (
        #= TODO: Float16 Broken due to being i16 in Julia=#
        Float32, Float64)
    append!(OCML_INTRINSICS, GCNIntrinsic.((
        :sin, :cos, :tan, :asin, :acos, :atan, :atan2,
        :sinh, :cosh, :tanh, :asinh, :acosh, :atanh,
        :sinpi, :cospi, :tanpi, :sincospi,
        :asinpi, :acospi, :atanpi, :atan2pi,
        :sqrt, :rsqrt, :cbrt, :rcbrt, :recip,
        :log, :log2, :log10, :log1p, :logb, :ilogb,
        :exp, :exp2, :exp10, :expm1,
        :erf, :erfinv, :erfc, :erfcinv, :erfcx,
        # TODO: :brev, :clz, :ffs, :byte_perm, :popc,
        :isnormal, :nearbyint, :nextafter,
        :pow, :pown, :powr,
        :tgamma, :j0, :j1, :y0, :y1,
    ); inp_args=(jltype,), out_arg=jltype))

    push!(OCML_INTRINSICS, GCNIntrinsic(:sin_fast, :native_sin; inp_args=(jltype,), out_arg=jltype))
    push!(OCML_INTRINSICS, GCNIntrinsic(:cos_fast, :native_cos; inp_args=(jltype,), out_arg=jltype))
    push!(OCML_INTRINSICS, GCNIntrinsic(:sqrt_fast, :native_sqrt; inp_args=(jltype,), out_arg=jltype))
    push!(OCML_INTRINSICS, GCNIntrinsic(:rsqrt_fast, :native_rsqrt; inp_args=(jltype,), out_arg=jltype))
    push!(OCML_INTRINSICS, GCNIntrinsic(:recip_fast, :native_recip; inp_args=(jltype,), out_arg=jltype))
    push!(OCML_INTRINSICS, GCNIntrinsic(:log_fast, :native_log; inp_args=(jltype,), out_arg=jltype))
    push!(OCML_INTRINSICS, GCNIntrinsic(:log2_fast, :native_log2; inp_args=(jltype,), out_arg=jltype))
    push!(OCML_INTRINSICS, GCNIntrinsic(:log10_fast, :native_log10; inp_args=(jltype,), out_arg=jltype))
    push!(OCML_INTRINSICS, GCNIntrinsic(:exp_fast, :native_exp; inp_args=(jltype,), out_arg=jltype))
    push!(OCML_INTRINSICS, GCNIntrinsic(:exp2_fast, :native_exp2; inp_args=(jltype,), out_arg=jltype))
    push!(OCML_INTRINSICS, GCNIntrinsic(:exp10_fast, :native_exp10; inp_args=(jltype,), out_arg=jltype))
    push!(OCML_INTRINSICS, GCNIntrinsic(:abs, :fabs; inp_args=(jltype,), out_arg=jltype))
    # TODO: abs(::Union{Int32,Int64})

    # FIXME: Multi-argument functions
    #=
    push!(OCML_INTRINSICS, = map(intr->GCNIntrinsic(intr), (
        :sincos, :frexp, :ldexp, :copysign,
    )))
    =#
    #push!(OCML_INTRINSICS, GCNIntrinsic(:ldexp; inp_args=(jltype,), out_arg=(jltype, Int32), isinverted=true))
end

let jltype=Float32
    # TODO: Float64 is broken for some reason, try to re-enable on a newer LLVM
    push!(OCML_INTRINSICS, GCNIntrinsic(:isfinite; inp_args=(jltype,), out_arg=Int32))
    push!(OCML_INTRINSICS, GCNIntrinsic(:isinf; inp_args=(jltype,), out_arg=Int32))
    push!(OCML_INTRINSICS, GCNIntrinsic(:isnan; inp_args=(jltype,), out_arg=Int32))
    push!(OCML_INTRINSICS, GCNIntrinsic(:signbit; inp_args=(jltype,), out_arg=Int32))
end

generate_intrinsic.(OCML_INTRINSICS)
