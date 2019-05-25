#=
mkpath(joinpath(@__DIR__, "bitcode"))
cd(joinpath(@__DIR__, "bitcode")) do
    mv(download("http://repo.radeon.com/rocm/apt/debian/pool/main/r/rocm-device-libs/rocm-device-libs_0.0.1_amd64.deb"), "./rocdevlibs.deb"; force=true)
    run(`ar x ./rocdevlibs.deb`)
    run(`tar xf ./data.tar.gz`)
    cd("./opt/rocm/lib") do
        for f in readdir(pwd())
            if splitext(f)[2] == ".bc"
                name = first(splitpath(f))
                path = joinpath("../../../", name)
                @info "Copying $name to $path"
                mv(f, path)
            end
        end
    end
    rm("./control.tar.gz")
    rm("./debian-binary")
    rm("./rocdevlibs.deb")
    rm("./data.tar.gz")
    rm("./opt/", recursive=true)
end
=#

cd(@__DIR__) do
    mv(download("https://home.jpsamaroo.me/bitcode.tar.gz"), "./bitcode.tar.gz"; force=true)
    run(`tar xf ./bitcode.tar.gz`)
    rm("./bitcode.tar.gz")
end
