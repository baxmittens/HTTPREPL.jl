module HTTPREPL


using HTTP
using JSON3
using Serialization
using JLD2
using Random
using Dates

struct Record
	vars::Dict{String,Any}
	code::Array{String}
	Record() = new(Dict{Symbol, Any}(), String[])
end

mutable struct HTTPREPLSettings
	IP::String
	PORT::Int64	
	PW::String
	evalmodule::Module
	arr::Array{Any}
	sendkwargs::Base.Pairs
	record::Record
	HTTPREPLSettings(IP::String,PORT::Int64,PW::String) = new(IP, PORT, PW, Main, Any[], pairs(()), Record())
end

const SETTINGS = HTTPREPLSettings("127.0.0.1", 1234, "HTTPREPL2024!")

function replacequotes!(ex::Expr, vars::Vector{Symbol}=Symbol[])
	if ex.head == :$
		@assert length(ex.args) == 1
		push!(vars, ex.args[1])
		return (true, ex.args[1], vars)
	end
	for (i,arg) in enumerate(ex.args)
		if isa(arg, Expr)
			isquoted,symb,_ = replacequotes!(arg, vars)
			if isquoted
				ex.args[i] = symb
			end
		end
	end
	return false,:_,vars
end

function gen_json_var_pairs(vars)
	ex = Expr(:tuple)
	for var in vars
		x = esc(var)
		y = Meta.quot(var)
		push!(ex.args,
			quote
				begin
					io = IOBuffer()
					serialize(io, $x)
					$y => take!(io)
				end
			end
		)
	end
	return ex
end

function send(payload)
	url = "http://$(SETTINGS.IP):$(SETTINGS.PORT)"
	headers = [("Content-Type", "application/json"), ("X-Auth-Creds", SETTINGS.PW)]
	r = HTTP.request("POST", url, headers, JSON3.write(payload); SETTINGS.sendkwargs...)
end

macro rREPL(expr)
	_,_,vars = replacequotes!(expr)
	varexp = gen_json_var_pairs(vars)
	evalcode = string(expr)
	push!(varexp.args,
		quote
			:evalcode => $evalcode
		end
		)
	return quote
		dict = Dict($varexp)
		send(dict)
	end
end

function setup!(;ip::String=SETTINGS.IP, port::Int64=SETTINGS.PORT, pw::String=SETTINGS.PW, evalmodule::Module=SETTINGS.evalmodule, sendkwargs::Base.Pairs=SETTINGS.sendkwargs)
	SETTINGS.IP = ip
	SETTINGS.PORT = port
	SETTINGS.PW = pw
	SETTINGS.evalmodule = evalmodule
	SETTINGS.sendkwargs = sendkwargs
	return nothing
end

function startrecord!()
	SETTINGS.record = Record()
	return nothing
end

function jld2loadstring(name::String, dict::Dict{String,Any})
	#vardict = Dict{String,Any}((x[1:2]=="##" ? "var\"$x\"" : x) => y for (x,y) in dict)
	#lstr = foldl((x,y)->x*", "*y, keys(vardict))
	#rstr = foldl((x,y)->x*", "*y, map(x->"\""*escape_string(x)*"\"", collect(keys(vardict))))
	lstr = foldl((x,y)->x*", "*y, keys(dict))
	rstr = foldl((x,y)->x*", "*y, map(x->"\""*escape_string(x)*"\"", collect(keys(dict))))
	return "$lstr = load(joinpath(@__DIR__, \"$name\"), $rstr)"
end

function writerecord!(filename::String=randstring(15)*".jl"; timestamp=true)
	splitstr = split(filename, ".jl")
	julia_filename = filename
	jld2_filename = filename
	if length(splitstr) == 1
		julia_filename *= ".jl"
		jld2_filename *= ".jld2"
	elseif length(splitstr) == 2 && splitstr[2] == ""
		jld2_filename *= "d2"
	else
		error("File ending error for filename: $filename")
	end
	dir1 = joinpath(".","rREPLRecords")
	if !isdir(dir1)
		#run(`mkdir $dir1`)
		mkdir(dir1)
	end
	if timestamp
		ts_str = Dates.format(now(), "yyyy_mm_dd_HH_MM_SS")
		dir2 = joinpath(".","rREPLRecords",ts_str*"_"*splitstr[1])
		JLD2_PATH = joinpath(".","rREPLRecords",ts_str*"_"*splitstr[1], jld2_filename)
		JULIA_PATH = joinpath(".","rREPLRecords",ts_str*"_"*splitstr[1], julia_filename)
	else
		dir2 = joinpath(".","rREPLRecords",splitstr[1])
		JLD2_PATH = joinpath(".","rREPLRecords",splitstr[1], jld2_filename)
		JULIA_PATH = joinpath(".","rREPLRecords",splitstr[1], julia_filename)
	end
	if !isdir(dir2)
		#run(`mkdir $dir2`)
		mkdir(dir2)
	end
	save(JLD2_PATH, SETTINGS.record.vars)
	open(JULIA_PATH, "w") do f
		write(f, "using JLD2\n")
		for codefragment ∈ SETTINGS.record.code
			for line ∈ split(codefragment, "\n")
				if !occursin("startrecord!()", strip(line)) && (occursin("import", strip(line)) || occursin("using", strip(line)))
					write(f, strip(line)*"\n")
				end
			end
		end
		write(f, jld2loadstring(jld2_filename, SETTINGS.record.vars)*"\n")
		for codefragment ∈ SETTINGS.record.code
			lines = split(codefragment, "\n")
			for (i,line) ∈ enumerate(lines)
				if !occursin("startrecord!()", strip(line)) && !occursin("import", strip(line)) && !occursin("using", strip(line))
					#if (i == 1 && strip(line)=="begin") || (i == length(lines) && strip(line)=="end") || (strip(line)[1:2]=="#=" && strip(line)[end-1:end]=="=#")
					if strip(line)[1:2]=="#=" && strip(line)[end-1:end]=="=#"
					else
						write(f, line*"\n")
					end
				end
			end
		end
    end
	SETTINGS.record = Record()
	return nothing
end

function varname(key)
	strkey = string(key)
	if length(strkey)>1 && strkey[1:2] == "##"
		return "var\"$strkey\""
	else
		return strkey
	end
end

function listen(; async=false)
	if async
		servefun = HTTP.serve!
	else
		servefun = HTTP.serve
	end
	server = servefun(SETTINGS.IP, SETTINGS.PORT) do request::HTTP.Request
		if !HTTP.headercontains(request, "X-Auth-Creds", SETTINGS.PW)
			return HTTP.Response(401, "Invalid credentials")
		end
		empty!(SETTINGS.arr)
		payload = Dict(JSON3.read(request.body))
		evalcode = pop!(payload, :evalcode)
		for (i,(key,val)) in enumerate(payload)
			push!(SETTINGS.arr, deserialize(IOBuffer(Vector{UInt8}(val))))
			#expr = Meta.parse("$(string(key))=HTTPREPL.SETTINGS.arr[$i]")
			#Base.eval(SETTINGS.evalmodule, expr)
			@eval SETTINGS.evalmodule $key = HTTPREPL.SETTINGS.arr[$i]
			#expr = Meta.parse("HTTPREPL.SETTINGS.record.vars[\"$(string(key))\"]=HTTPREPL.SETTINGS.arr[$i]")
			#Base.eval(SETTINGS.evalmodule, expr)
			@eval SETTINGS.evalmodule HTTPREPL.SETTINGS.record.vars[$(varname(key))] = HTTPREPL.SETTINGS.arr[$i]
		end
		expr = Meta.parse(evalcode)
		#Base.eval(SETTINGS.evalmodule, expr)
		@eval SETTINGS.evalmodule $expr
		push!(SETTINGS.record.code, evalcode)
		return HTTP.Response(200, "ok")
	end
	return server
end

export @rREPL, deserialize, startrecord!, writerecord!

end # module HTTPREPL
