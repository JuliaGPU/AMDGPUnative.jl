# OpenCL runtime interface to AMDGPUnative
using OpenCL
#const cl = OpenCL.cl

include("opencl/args.jl")
include("opencl/buffer.jl")

const OCL_DEFAULT_DEVICE = Ref{cl.Device}()
const OCL_DEFAULT_CONTEXT = IdDict{cl.Device,cl.Context}()
const OCL_DEFAULT_CMDQUEUE = IdDict{cl.Device,cl.CmdQueue}()
devs = cl.devices()
if length(devs) > 0
    dev = first(devs)
    OCL_DEFAULT_DEVICE[] = dev
    ctx = cl.Context(dev)
    OCL_DEFAULT_CONTEXT[dev] = ctx
    queue = cl.CmdQueue(ctx)
    OCL_DEFAULT_CMDQUEUE[dev] = queue
end

default_device(::typeof(HSA)) = OCL_DEFAULT_DEVICE[]

function default_queue(::typeof(HSA), device)
    cldev = device.device
    if !haskey(OCL_DEFAULT_CMDQUEUE, cldev)
        if !haskey(OCL_DEFAULT_CONTEXT, cldev)
            ctx = cl.Context(cldev)
            OCL_DEFAULT_CONTEXT[cldev] = ctx
        else
            ctx = OCL_DEFAULT_CONTEXT[cldev]
        end
        queue = cl.CmdQueue(ctx)
        OCL_DEFAULT_CMDQUEUE[cldev] = queue
        return queue
    else
        return OCL_DEFAULT_CMDQUEUE[cldev]
    end
end
get_device(queue::RuntimeQueue{cl.CmdQueue}) =
    RuntimeDevice(queue.queue[:device])
get_context(queue::cl.CmdQueue) = queue[:context]

default_isa(device::RuntimeDevice{cl.Device}) =
    device.device[:name]

#create_event(device::RuntimeDevice{cl.Device}) =
#    RuntimeEvent(cl.UserEvent(device.device))

function create_executable(::typeof(OCL), device, func)
    data = link_kernel(func)
    binaries = Dict{cl.Device, Array{UInt8}}()
    binaries[device.device] = data
    dev = device.device
    ctx = OCL_DEFAULT_CONTEXT[dev]
    return cl.Program(ctx, binaries=binaries) |> cl.build!
end

create_kernel(::typeof(HSA), device, exe, entry, args) =
    cl.Kernel(exe.exe, entry)
struct FakeDeviceArray
    size::Int64
    ptr::Int64
end
clconvert(q, x) = x
function clconvert(q, x::ROCDeviceArray{T,N,A}) where {T,N,A}
    #=
    cl_mem cm_buffer;
    cm_buffer = clCreateBuffer(cxContext, CL_MEM_READ_ONLY, sizeof(st_foo), NULL, NULL);
    clSetKernelArg(ckKernel, 0, sizeof(cl_mem), (void*)&cm_buffer);
    clEnqueueWriteBuffer(cqueue, cm_buffer, CL_TRUE, 0, sizeof(st_foo), &stVar, 0, NULL, NULL);
    =#
    @show x
    #=
    @show sizeof(x)
    xref = Ref(x)
    GC.@preserve xref begin
        xptr = Base.unsafe_convert(Ptr{UInt32}, Base.pointer_from_objref(xref))
        struct_size = div(sizeof(x),sizeof(UInt32))
        @show struct_size
        arr = unsafe_wrap(Array, xptr, (struct_size,))
        @show arr
        ctx = get_context(q)
        buf = cl.Buffer(UInt32, ctx, (:rw, :copy); hostbuf=arr)
        @show buf
    end
    return buf
    =#
    return FakeDeviceArray(prod(x.shape), Int64(x.ptr))
end
function launch_kernel(::typeof(HSA), queue, kern;
                       groupsize=nothing, gridsize=nothing)
    q = queue.queue
    k = kern.kernel
    args = map(arg->clconvert(q, arg), kern.args)
    @show typeof.(args)
    cl.set_args!(k, args...)
    event = cl.enqueue_kernel(q, k, 1, nothing) #=gridsize, groupsize,=#
    return RuntimeEvent(event)
end
