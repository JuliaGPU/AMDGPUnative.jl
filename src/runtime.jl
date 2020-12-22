struct RuntimeDevice{D}
    device::D
end
default_device() = RuntimeDevice(default_device(RUNTIME[]))
default_device(::typeof(HSA_rt)) = HSARuntime.get_default_agent()

struct RuntimeQueue{Q}
    queue::Q
end
default_queue(device) = RuntimeQueue(default_queue(RUNTIME[], device))
default_queue(::typeof(HSA_rt), device) =
    HSARuntime.get_default_queue(device.device)
get_device(queue::RuntimeQueue{HSAQueue}) = RuntimeDevice(queue.queue.agent)

default_isa(device::RuntimeDevice{HSAAgent}) =
    HSARuntime.get_first_isa(device.device)

struct RuntimeEvent{E}
    event::E
end
create_event(exe) = RuntimeEvent(create_event(RUNTIME[], exe))
Base.wait(event::RuntimeEvent, exe) = wait(event.event, exe)

"Tracks the completion and status of a kernel's execution."
struct HSAStatusSignal
    signal::HSASignal
    exe::HSAExecutable
end
create_event(::typeof(HSA_rt), exe) = HSAStatusSignal(HSASignal(), exe.exe)
function Base.wait(event::RuntimeEvent{HSAStatusSignal}; kwargs...)
    wait(event.event.signal; kwargs...) # wait for completion signal
    exe = event.event.exe
    agent = exe.agent
    if haskey(exe.globals, :__global_exception_flag)
        ex_flag = HSARuntime.get_global(exe, :__global_exception_flag)
        ex_flag_ptr = Base.unsafe_convert(Ptr{Int64}, ex_flag)
        ex_flag_value = Base.unsafe_load(ex_flag_ptr)
        if ex_flag_value != 0
            if haskey(exe.globals, :__global_exception_ring)
                ex_ring = HSARuntime.get_global(exe, :__global_exception_ring)
                ex_ring_ptr = Base.unsafe_convert(Ptr{ExceptionEntry}, ex_ring)
                ex_ring_value = Base.unsafe_load(ex_ring_ptr)
                # FIXME: Check for and collect any exceptions, and clear their slots
                # FIXME: Throw appropriate error
                throw(KernelException(RuntimeDevice(agent)))
            else
                throw(KernelException(RuntimeDevice(agent)))
            end
        end
    end
end


struct RuntimeExecutable{E}
    exe::E
end
create_executable(device, entry, obj; globals=()) =
    RuntimeExecutable(create_executable(RUNTIME[], device, entry, obj; globals=globals))
function create_executable(::typeof(HSA_rt), device, entry, obj; globals=())
    # link with ld.lld
    ld_path = HSARuntime.ld_lld_path
    @assert ld_path != "" "ld.lld was not found; cannot link kernel"
    path_exe = mktemp() do path_o, io_o
        write(io_o, obj)
        flush(io_o)
        path_exe = path_o*".exe"
        run(`$ld_path -shared -o $path_exe $path_o`)
        path_exe
    end
    data = read(path_exe)
    rm(path_exe)

    return HSAExecutable(device.device, data, entry; globals=globals)
end
HSARuntime.get_global(exe::RuntimeExecutable, sym::Symbol) =
    HSARuntime.get_global(exe.exe, sym)

struct RuntimeKernel{K}
    kernel::K
end
create_kernel(device, exe, entry, args) =
    RuntimeKernel(create_kernel(RUNTIME[], device, exe, entry, args))
create_kernel(::typeof(HSA_rt), device, exe, entry, args) =
    HSAKernelInstance(device.device, exe.exe, entry, args)
launch_kernel(queue, kern, event; kwargs...) =
    launch_kernel(RUNTIME[], queue, kern, event; kwargs...)
function launch_kernel(::typeof(HSA_rt), queue, kern, event;
                       groupsize=nothing, gridsize=nothing)
    signal = event.event isa HSAStatusSignal ? event.event.signal : event.event
    HSARuntime.launch!(queue.queue, kern.kernel, signal;
                       workgroup_size=groupsize, grid_size=gridsize)
end
