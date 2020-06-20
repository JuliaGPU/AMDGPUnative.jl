export malloc, free

function malloc(sz::Csize_t)
    malloc_gbl = get_global_pointer(Val(:__global_malloc_hostcall),
                                    HostCall{UInt64,DevicePtr{UInt8,AS.Global},Tuple{Csize_t}})
    malloc_hc = Base.unsafe_load(malloc_gbl)
    ptr = hostcall!(malloc_hc, sz)
    if UInt64(ptr) != 0
        kernel_metadata_insert!(ptr, sz)
    end
    return ptr
end

function free(ptr::DevicePtr{T,AS.Global}) where T
    free_gbl = get_global_pointer(Val(:__global_free_hostcall),
                                  HostCall{UInt64,Nothing,Tuple{DevicePtr{UInt8,AS.Global}}})
    free_hc = Base.unsafe_load(free_gbl)
    hostcall!(free_hc, Base.unsafe_convert(DevicePtr{UInt8,AS.Global}, ptr))
    kernel_metadata_delete!(ptr)
end

# metadata store
struct MetadataInsertException <: Exception
    kern::UInt64
end
function Base.showerror(io::IO, mae::MetadataInsertException)
    print(io, "MetadataInsertException: Failed to insert metadata for kernel ")
    print(io, mae.kern)
end
function kernel_metadata_insert!(ptr, sz)
    metadata_gbl = get_global_pointer(Val(:__global_metadata_store), KernelMetadata)
    offset = 1
    while true
        # FIXME: atomic_load
        metadata = Base.unsafe_load(metadata_gbl, offset)
        if metadata.kern == 0
            # empty metadata slot, use it
            # FIXME: atomic_store!
            Base.unsafe_store!(metadata_gbl, KernelMetadata(_completion_signal(), ptr, sz), offset)
            return true
        elseif metadata.kern == 1
            # tail slot, error
            # FIXME: throw(MetadataInsertException(_completion_signal()))
            return false
        else
            # slot in use, skip it
            offset += 1
        end
    end
end
function kernel_metadata_delete!(ptr)
    metadata_gbl = get_global_pointer(Val(:__global_metadata_store), KernelMetadata)
    offset = 1
    our_signal = _completion_signal()
    while true
        # FIXME: atomic_load
        metadata = Base.unsafe_load(metadata_gbl, offset)
        if metadata.kern == our_signal
            # our slot, clear it
            # FIXME: atomic_store!
            metadata_gbl_ptr = convert(DevicePtr{UInt8,AS.Global},
                                       Base.unsafe_convert(Ptr{KernelMetadata}, metadata_gbl) +
                                       (sizeof(KernelMetadata)*(offset-1)))
            memset!(metadata_gbl_ptr, 0x0, Csize_t(sizeof(KernelMetadata)))
            return true
        elseif metadata.kern == 1
            # tail slot, error
            # FIXME: throw(MetadataDeleteException(_completion_signal()))
            return false
        else
            # not our slot, skip it
            offset += 1
        end
    end
end
