const deviceptr_source = """
__kernel void getPtr(__global ulong *ptr, __global ulong *out) {
    out[0] = &ptr[0];
}
"""

const DEVICEPTR_KERNELS = Dict{cl.Device,cl.Kernel}()

function get_deviceptr(q::cl.CmdQueue, buf::cl.Buffer{T}) where T
    ctx = q[:context]
    dev = q[:device]

    host_buf = cl.Buffer(UInt64, ctx, :rw, 1)
    dev_buf = cl.Buffer(UInt64, ctx, :rw, 1)

    if !haskey(DEVICEPTR_KERNELS, dev)
        prog = cl.build!(cl.Program(ctx, source=deviceptr_source), options="-Werror")
        kern = cl.Kernel(prog, "getPtr")
        DEVICEPTR_KERNELS[dev] = kern
    else
        kern = DEVICEPTR_KERNELS[dev]
    end

    event = q(kern, 1, nothing, host_buf, dev_buf)
    cl.wait(event)
    return Ptr{T}(cl.read(q, dev_buf)[1])
end
