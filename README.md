# HTTPREPL.jl
Evaluate Julia Code on a remote REPL over HTTP.

This package is in a early development stage. There is an other Julia package, named (RemoteREPL.jl)[https://github.com/JuliaWeb/RemoteREPL.jl], which likely works better in most cases.

## Install

```julia
import Pkg
Pkg.add(url="https://github.com/baxmittens/HTTPREPL.jl.git")
```

## Usage

I will briefly describe my use-case here. Other applications are possible; the code may have to be extended for this. This should be relatively easy.

Setting:

Worker A: my local desktop with display and GPU.
Worker B: compute server without display, GPU, X11, or else.

Worker A:
```julia
using HTTPREPL
HTTPREPL.setup!(ip="ip of worker A", port=1234, pw="test1234!")
HTTPREPL.listen()
```

Worker B:
```julia
using HTTPREPL
HTTPREPL.setup!(ip="ip of worker A", port=1234, pw="test1234!")

x = 0:.1:2π
y = sin.(x)

@rREPL begin
    using CairoMakie
    f = Figure();
    ax = Axis(f[1,1])
    lines!(ax, $x, $y)
    display(f)
end
```

Result: Plot appears on worker A.
