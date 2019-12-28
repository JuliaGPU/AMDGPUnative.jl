## interop with cl.Buffer
function Base.convert(::Type{ROCDeviceArray{T,N,AS.Global}}, a::cl.Buffer{T}) where {T,N}
    dev_ptr = get_deviceptr(default_queue(default_device()).queue, a)
    @show dev_ptr
    ROCDeviceArray{T,N,AS.Global}((length(a),), DevicePtr{T,AS.Global}(dev_ptr))
end

Adapt.adapt_storage(::Adaptor, xs::cl.Buffer{T}) where T =
    convert(ROCDeviceArray{T,ndims(xs),AS.Global}, xs)
