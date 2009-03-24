#!/usr/bin/env lua5.1

local MDDIFF = 'mddiff'

function log(msg)
--	io.stderr:write(msg,'\n')
end

function receive(inf,outfile)
	local outf = assert(io.open(outfile,"w"))

	local line = inf:read("*l")
	local len = tonumber(line:match('^chunk (%d+)'))
	while len > 0 do
		local next_chunk = 4096
		if len < next_chunk then next_chunk = len end
		local data = inf:read(next_chunk)
		len = len - data:len()
		outf:write(data)
	end
	outf:close()
end

function receive_delta(inf)
	local cmds = {}
	local line = ""

	repeat
		log('receiving '..#cmds)
		line = inf:read("*l")
		--log('received '..line)
		if line ~= "END" then cmds[#cmds+1] = line end
	until line == "END"

	return cmds
end

function tmp_for(path)
	local newpath = path .. '.new'
	assert(os.execute('test -f '..newpath) ~= 0)
	return newpath
end

function execute(cmd)
	local opcode = cmd:match('^(%S+)')

	if opcode == "ADD" then
		local name, hsha, bsha = cmd:match('ADD (%S+) (%S+) (%S+)')
		local exists = os.execute('test -f '..name)
		if exists == 0 then
			local inf = io.popen(MDDIFF .. ' ' .. name)
			local hsha_l, bsha_l = 
				inf:read('*a'):match('(%S+) (%S+)')
			if hash == hsha_l and bsha == bsha_l then
				log('skipping '..name..' already there')
				return
			end
		end
		local tmpfile = tmp_for(name)
		io.stdout:write('GET '..name..'\n')
		io.stdout:flush()
		receive(io.stdin, tmpfile)
		os.rename(tmpfile, name)
		log('added '..name)
	elseif opcode == "DELETE" then
		local name, hsha, bsha = cmd:match('DELETE (%S+) (%S+) (%S+)')
		local exists = os.execute('test -f '..name)
		if exists then
			local inf = io.popen(MDDIFF .. ' ' .. name)
			local hsha_l, bsha_l = 
				inf:read('*a'):match('(%S+) (%S+)')
			if hsha == hsha_l and bsha == bsha_l then
				log('deleting '..name)
				os.remove(name)
				return
			end
		end
		log('already deleted '..name)
	elseif opcode == "REPLACEHEADER" then
		local name1, hsha1, name2, hsha2 = 
			cmd:match('REPLACEHEADER (%S+) (%S+) WITH (%S+) (%S+)')

		error('non implemented opcode '..opcode)
	elseif opcode == "COPY" then
		local name_src, hsha, bsha, name_tgt = 
			cmd:match('COPY (%S+) (%S+) (%S+) TO (%S+)')
		local exists = os.execute('test -f '..name_src)
		if exists then
			local inf = io.popen(MDDIFF .. ' ' .. name_src)
			local hsha_l, bsha_l = inf:read('*a'):match('(%S+) (%S+)')
			if hsha == hsha_l and bsha == bsha_l then
				log('copying '..name_src)
				local ok = os.execute('cp '..name_src..' '..name_tgt)
				if ok == 0 then return
				else error('cp failed')
				end
			end
		else
			local tmpfile = tmp_for(name_tgt)
			io.stdout:write('GET '..name_tgt..'\n')
			io.stdout:flush()
			receive(io.stdin, tmpfile)
			os.rename(tmpfile, name_tgt)
			log('added '..name_tgt)
		end
	elseif opcode == "REPLACE" then
		local name1, hsha1, bsha1, name2, hsha2, bsha2 = 
		   cmd:match('REPLACE (%S+) (%S+) (%S+) WITH (%S+) (%S+) (%S+)')

	else
		error('Unknown opcode '..opcode)
	end
end

local commands = receive_delta(io.stdin)
log('delta received')
for _,cmd in ipairs(commands) do
	execute(cmd)
end
log('committing')
io.stdout:write('COMMIT\n')
io.stdout:flush()
os.exit(0)

-- vim:set ts=4:
