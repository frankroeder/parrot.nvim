local Pool = {}
Pool.__index = Pool

--- Creates a new Pool instance.
--- @return table
function Pool:new()
  return setmetatable({ _processes = {} }, self)
end

--- Adds a process to the pool.
--- @param job table # A plenary job.
--- @param buf number|nil # The buffer number (optional)
function Pool:add(job, buf)
  table.insert(self._processes, { job = job, buf = buf })
end

--- Checks if there is no other process running for the given buffer.
--- @param buf number|nil # The buffer number (optional)
--- @return boolean # True if no other process is running for the buffer, false otherwise.
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

--- Removes the process with the specified PID from the pool.
--- @param pid number # The process ID to find the corresponding handle.
function Pool:remove(pid)
  for i, handle_info in self:ipairs() do
    if handle_info.job.pid == pid then
      table.remove(self._processes, i)
      return
    end
  end
end

--- Checks if the pool is empty.
--- @return boolean
function Pool:is_empty()
  return next(self._processes) == nil
end

--- Returns an iterator function for the processes in the pool.
function Pool:ipairs()
  return ipairs(self._processes)
end

return Pool
