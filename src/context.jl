##
# Implements contextual dispatch through Cassette.jl
# Goals:
# - Rewrite common CPU functions to appropriate GPU intrinsics
#
# TODO:
# - error (erf, ...)
# - pow
# - min, max
# - mod, rem
# - gamma
# - bessel
# - distributions
# - unsorted

using Cassette

function transform(ctx, ref)
    CI = ref.code_info
    noinline = any(@nospecialize(x) ->
                       Core.Compiler.isexpr(x, :meta) &&
                       x.args[1] == :noinline,
                   CI.code)
    CI.inlineable = !noinline

    CI.ssavaluetypes = length(CI.code)
    # Core.Compiler.validate_code(CI)
    return CI
end

const InlinePass = Cassette.@pass transform

Cassette.@context ROCCtx
const rocctx = Cassette.disablehooks(ROCCtx(pass = InlinePass))

###
# Cassette fixes
###

# kwfunc fix
Cassette.overdub(::ROCCtx, ::typeof(Core.kwfunc), f) = return Core.kwfunc(f)

# the functions below are marked `@pure` and by rewritting them we hide that from
# inference so we leave them alone (see https://github.com/jrevels/Cassette.jl/issues/108).
@inline Cassette.overdub(::ROCCtx, ::typeof(Base.isimmutable), x)     = return Base.isimmutable(x)
@inline Cassette.overdub(::ROCCtx, ::typeof(Base.isstructtype), t)    = return Base.isstructtype(t)
@inline Cassette.overdub(::ROCCtx, ::typeof(Base.isprimitivetype), t) = return Base.isprimitivetype(t)
@inline Cassette.overdub(::ROCCtx, ::typeof(Base.isbitstype), t)      = return Base.isbitstype(t)
@inline Cassette.overdub(::ROCCtx, ::typeof(Base.isbits), x)          = return Base.isbits(x)

@inline Cassette.overdub(::ROCCtx, ::typeof(datatype_align), ::Type{T}) where {T} = datatype_align(T)

###
# Rewrite functions
###
Cassette.overdub(ctx::ROCCtx, ::typeof(isdevice)) = true

# libdevice.jl
for f in (:cos, :cospi, :sin, :sinpi, :tan,
          :acos, :asin, :atan,
          :cosh, :sinh, :tanh,
          :acosh, :asinh, :atanh,
          :log, :log10, :log1p, :log2,
          :exp, :exp2, :exp10, :expm1, :ldexp,
          :isfinite, :isinf, :isnan,
          :signbit, :abs,
          :sqrt, :cbrt,
          :ceil, :floor,)
    @eval function Cassette.overdub(ctx::ROCCtx, ::typeof(Base.$f), x::Union{Float32, Float64})
        @Base._inline_meta
        return AMDGPUnative.$f(x)
    end
end

contextualize(f::F) where F = (args...) -> Cassette.overdub(rocctx, f, args...)
