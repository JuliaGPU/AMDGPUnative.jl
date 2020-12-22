@testset "Exceptions" begin

function oob_kernel(X)
    X[0] = 1
    nothing
end

HA = HSAArray(ones(Float32, 4))
_, msg = @grab_output(@test_throws AMDGPUnative.KernelException wait(@roc oob_kernel(HA)), stdout)
@test startswith(msg, "ERROR: an exception was thrown during kernel execution.\n")

end
