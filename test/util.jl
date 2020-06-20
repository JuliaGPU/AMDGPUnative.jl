# NOTE: based on test/pkg.jl::capture_stdout, but doesn't discard exceptions
macro grab_output(ex, io=stdout)
    quote
        mktemp() do fname, fout
            ret = nothing
            open(fname, "w") do fout
                if $io == stdout
                    redirect_stdout(fout) do
                        ret = $(esc(ex))
                    end
                elseif $io == stderr
                    redirect_stderr(fout) do
                        ret = $(esc(ex))
                    end
                end
            end
            ret, read(fname, String)
        end
    end
end
