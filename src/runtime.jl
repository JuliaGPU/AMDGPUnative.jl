struct RuntimeDevice{D}
    device::D
end
default_device() = RuntimeDevice(default_device(RUNTIME[]))
default_device(::typeof(HSA)) = HSARuntime.get_default_agent()

struct RuntimeQueue{Q}
    queue::Q
end
default_queue(device) = RuntimeQueue(default_queue(RUNTIME[], device))
default_queue(::typeof(HSA), device) =
    HSARuntime.get_default_queue(device.device)
get_device(queue::RuntimeQueue{HSAQueue}) = RuntimeDevice(queue.queue.agent)

default_isa(device::RuntimeDevice{HSAAgent}) =
    HSARuntime.get_first_isa(device.device)

struct RuntimeEvent{E}
    event::E
end
#create_event(device::RuntimeDevice{HSAAgent}) = RuntimeEvent(HSASignal())
Base.wait(event::RuntimeEvent) = wait(event.event)

struct RuntimeExecutable{E}
    exe::E
end
create_executable(device, func) =
    RuntimeExecutable(create_executable(RUNTIME[], device, func))
function create_executable(::typeof(HSA), device, func)
    data = link_kernel(func)

    return HSAExecutable(device.device, data, func.entry)
end

struct RuntimeKernel{K,A}
    kernel::K
    args::A
end
create_kernel(device, exe, entry, args) =
    RuntimeKernel(create_kernel(RUNTIME[], device, exe, entry, args), args)
create_kernel(::typeof(HSA), device, exe, entry, args) =
    HSAKernelInstance(device.device, exe.exe, entry, args)
launch_kernel(queue, kern; kwargs...) =
    launch_kernel(RUNTIME[], queue, kern; kwargs...)
function launch_kernel(::typeof(HSA), queue, kern;
                       groupsize=nothing, gridsize=nothing)
    signal = HSASignal()
    HSARuntime.launch!(queue.queue, kern.kernel, signal;
                       workgroup_size=groupsize, grid_size=gridsize)
    return RuntimeEvent(signal)
end
