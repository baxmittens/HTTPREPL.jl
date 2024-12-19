include("../src/HTTPREPL.jl")

HTTPREPL.setup!(sendkwargs=pairs((proxy=nothing,)))

N = 100_000
x = rand(Float64, N)

HTTPREPL.@rREPL display($x)