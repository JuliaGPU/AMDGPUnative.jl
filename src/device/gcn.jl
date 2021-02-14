include(joinpath("gcn", "intrinsics.jl"))
if Base.libllvm_version >= v"7.0"
    include(joinpath("gcn", "ocml.jl"))
    include(joinpath("gcn", "ockl.jl"))
end
include(joinpath("gcn", "indexing.jl"))
include(joinpath("gcn", "assertion.jl"))
include(joinpath("gcn", "synchronization.jl"))
include(joinpath("gcn", "memory_static.jl"))
include(joinpath("gcn", "memory_dynamic.jl"))
include(joinpath("gcn", "hostcall.jl"))
include(joinpath("gcn", "output.jl"))
