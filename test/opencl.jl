using OpenCL
AMDGPUnative.RUNTIME[] = AMDGPUnative.OCL
using LinearAlgebra

if cl.api.libopencl != "" && length(cl.devices()) > 0
@testset "OpenCL runtime integration" begin

@test typeof(AMDGPUnative.default_device().device) <: cl.Device

function mysum(X,Y,Z)
    idx = AMDGPUnative.workitemIdx_x()
    Z[idx] = X[idx] + Y[idx]
    nothing
end

dev = AMDGPUnative.default_device()
q = AMDGPUnative.default_queue(dev).queue
dev = dev.device
ctx = AMDGPUnative.get_context(q)

A = rand(Float32, 8)
B = rand(Float32, 8)

A_ = cl.Buffer(Float32, ctx, (:rw, :copy), hostbuf=A)
B_ = cl.Buffer(Float32, ctx, (:rw, :copy), hostbuf=B)
C_ = cl.Buffer(Float32, ctx, :rw, length(A))

@test Base.unsafe_convert(Ptr{Nothing}, A_.id) != AMDGPUnative.get_deviceptr(q, A_)

@roc groupsize=1 gridsize=1 mysum(A_,B_,C_)

cl.finish(q)
C = cl.read(q, C_)
@test all(x->x>0, C)
@test isapprox(norm(C - (A+B)), zero(Float32))

end # @testset
end # if
