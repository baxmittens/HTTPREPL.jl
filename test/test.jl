using HTTPREPL

HTTPREPL.setup!(sendkwargs=pairs((proxy=nothing,)))

N = 100_000
x = rand(Float64, N)
y = rand(Float64, N)

HTTPREPL.@rREPL startrecord!()
HTTPREPL.@rREPL begin
	using GLMakie
	f = Figure()
	ax = Axis(f[1,1])
end
HTTPREPL.@rREPL lines!(ax, $x, $y)
HTTPREPL.@rREPL using Dates
using Dates
adate = now()
HTTPREPL.@rREPL display($adate)
HTTPREPL.@rREPL display(f)
HTTPREPL.@rREPL writerecord!()