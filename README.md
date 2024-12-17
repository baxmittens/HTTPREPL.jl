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

Machine A: server without display, GPU, X11, or else.
Machine B: my local desktop with display and GPU.


Machine A:
```julia
using HTTPREPL
HTTPREPL.setup!(ip="127.0.0.1", port=1234, pw="test1234!")
HTTPREPL.listen()
```

Machine B:
```julia
using HTTPREPL
HTTPREPL.setup!(ip="127.0.0.1", port=1234, pw="test1234!")

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

Result: Plot appears on machine B.
