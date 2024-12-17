module HTTPREPL


using HTTP
using JSON3
using Serialization

mutable struct HTTPREPLSettings
	IP::String
	PORT::Int64	
	PW::String
	dict::Dict{Symbol,Any}
	HTTPREPLSettings(IP::String,PORT::Int64,PW::String) = new(IP, PORT, PW)
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
	r = HTTP.request("POST", url, headers, JSON3.write(payload))
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

function setup!(;ip::String=SETTINGS.IP, port::Int64=SETTINGS.PORT, pw::String=SETTINGS.PW)
	SETTINGS.IP = ip
	SETTINGS.PORT = port
	SETTINGS.PW = pw
	return nothing
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
		payload = Dict(JSON3.read(request.body))
		evalcode = pop!(payload, :evalcode)
		for (key,val) in payload
			expr = Meta.parse("$(string(key))=deserialize(IOBuffer(Vector{UInt8}($val)))")
			Base.eval(expr)
		end
		expr = Meta.parse(evalcode)
		Base.eval(expr)
		return HTTP.Response(200, "ok")
	end
	return server
end

export @rREPL

end # module HTTPREPL
