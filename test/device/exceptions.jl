@testset "Exceptions" begin

function oob_kernel(X)
    @rocprintln("Testing 1...2...3...") # FIXME: This shouldn't be required
    X[0] = 1
    nothing
end

HA = HSAArray(ones(Float32, 4))
ev = @roc oob_kernel(HA)
@test_throws AMDGPUnative.KernelException wait(ev)

end
