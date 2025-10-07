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
--- @param qid string|nil # The query ID (optional)
--- @param target_type string|nil # The target type (optional) - "chat", "rewrite", "popup", etc.
function Pool:add(job, buf, qid, target_type)
  table.insert(self._processes, {
    job = job,
    buf = buf,
    qid = qid,
    target_type = target_type,
    timestamp = os.time(),
  })
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

--- Gets processes for a specific buffer.
--- @param buf number # The buffer number
--- @return table # List of process info tables for the buffer
function Pool:get_for_buffer(buf)
  local result = {}
  for _, process_info in ipairs(self._processes) do
    if process_info.buf == buf then
      table.insert(result, process_info)
    end
  end
  return result
end

--- Gets the most recent active job (by timestamp).
--- @return table|nil # The most recent process info, or nil if pool is empty
function Pool:get_active_job()
  if self:is_empty() then
    return nil
  end

  local most_recent = nil
  for _, process_info in ipairs(self._processes) do
    if most_recent == nil or process_info.timestamp > most_recent.timestamp then
      most_recent = process_info
    end
  end
  return most_recent
end

--- Stops jobs for a specific buffer.
--- @param buf number # The buffer number
--- @param signal number|nil # Signal to send (default 15)
--- @return number # Number of jobs stopped
function Pool:stop_buffer(buf, signal)
  signal = signal or 15
  local stopped_count = 0

  for i = #self._processes, 1, -1 do
    local process_info = self._processes[i]
    if process_info.buf == buf then
      if process_info.job.handle ~= nil and not process_info.job.handle:is_closing() then
        vim.uv.kill(process_info.job.pid, signal)
        stopped_count = stopped_count + 1
      end
      table.remove(self._processes, i)
    end
  end

  return stopped_count
end

--- Checks if there are any active jobs in the pool.
--- @return boolean # True if there are active jobs, false otherwise
function Pool:has_active_jobs()
  return not self:is_empty()
end

return Pool
