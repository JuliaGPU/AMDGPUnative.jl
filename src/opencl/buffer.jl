## interop with cl.Buffer
function Base.convert(::Type{ROCDeviceArray{T,N,AS.Global}}, a::cl.Buffer{T}) where {T,N}
    ROCDeviceArray{T,N,AS.Global}((length(a),), DevicePtr{T,AS.Global}(a.id))
end

Adapt.adapt_storage(::Adaptor, xs::cl.Buffer{T}) where T =
    convert(ROCDeviceArray{T,ndims(xs),AS.Global}, xs)
