
local M = {
	_handles = {}, -- handles for running processes
}

-- add a process handle and its corresponding pid to the _handles table
---@param job plenary.job # a plenary job
---@param buf number | nil # buffer number
M.add = function(job, buf)
	table.insert(M._handles, { job = job, buf = buf })
end

--- Check if there is no other pid running for the given buffer
---@param buf number | nil # buffer number
---@return boolean
M.can_handle = function(buf)
	if buf == nil then
		return true
	end
	for _, handle_info in ipairs(M._handles) do
		if handle_info.buf == buf then
			return false
		end
	end
	return true
end

-- remove a process handle from the _handles table using its pid
---@param pid number # the process id to find the corresponding handle
M.remove = function(pid)
	for i, handle_info in ipairs(M._handles) do
		if handle_info.job.pid == pid then
			table.remove(M._handles, i)
			return
		end
	end
end

M.clear= function()
  M._handles = {}
end

M.is_empty = function()
	return M._handles == {}
end

M.ipairs = function()
	return ipairs(M._handles)
end

return M
