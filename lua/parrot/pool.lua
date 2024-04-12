local Pool = {}
Pool.__index = Pool

function Pool:new()
  local o = { _processes = {} }
  setmetatable(o, self)
  self.__index = self
  return o
end

-- add a process to the pool
---@param job plenary.job # a plenary job
---@param buf number | nil # buffer number
function Pool:add(job, buf)
  table.insert(self._processes, { job = job, buf = buf })
end

--- Check if there is no other pid running for the given buffer
---@param buf number | nil # buffer number
---@return boolean
function Pool:unique_for_buffer(buf)
  if buf == nil then
    return true
  end
  for _, handle_info in self:ipairs() do
    if handle_info.buf == buf then
      return false
    end
  end
  return true
end

-- remove the process with "pid" from the pool
---@param pid number # the process id to find the corresponding handle
function Pool:remove(pid)
  for i, handle_info in self:ipairs() do
    if handle_info.job.pid == pid then
      table.remove(self._processes, i)
      return
    end
  end
end

function Pool:is_empty()
  return self._processes == {}
end

function Pool:ipairs()
  return ipairs(self._processes)
end

return Pool
