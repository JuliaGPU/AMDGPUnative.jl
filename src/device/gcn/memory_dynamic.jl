export malloc

function malloc(sz::Csize_t)
    malloc_gbl = get_global_pointer(Val(:__global_malloc_hostcall),
                                    HostCall{UInt64,DevicePtr{UInt8,AS.Global},Csize_t})
    malloc_hc = Base.unsafe_load(malloc_gbl)
    ptr = hostcall!(malloc_hc, sz)
    if Int64(ptr) != 0
        kernel_metadata_append!(ptr, sz)
    end
    return ptr
end

# metadata store
struct MetadataAppendException <: Exception
    kern::UInt64
end
function Base.showerror(io::IO, mae::MetadataAppendException)
    print(io, "MetadataAppendException: Failed to append metadata for kernel ")
    print(io, mae.kern)
end
function kernel_metadata_append!(ptr, sz)
    metadata_gbl = get_global_pointer(Val(:__global_metadata_store), KernelMetadata)
    offset = 1
    while true
        # FIXME: atomic_load
        metadata = Base.unsafe_load(metadata_gbl, offset)::KernelMetadata
        if metadata.kern == 0
            # empty metadata slot, use it
            # FIXME: atomic_store!
            Base.unsafe_store!(metadata_gbl, offset, KernelMetadata(_completion_signal(), ptr, sz))
            return
        elseif metadata.kern == 1
            # tail slot, error
            throw(MetadataAppendException(_completion_signal()))
        else
            # slot in use, skip it
            offset += 1
        end
    end
end
