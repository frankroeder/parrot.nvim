local logger = require("parrot.logger")

local Queries = {}
Queries.__index = Queries

--- Creates a new Queries instance.
--- @return table
function Queries:new()
  return setmetatable({ _queries = {} }, self)
end

--- Adds a query to the collection.
--- @param qid number # Query ID.
--- @param data table # Query data.
function Queries:add(qid, data)
  -- Initialize cancellation state
  data.cancelled = false
  data.cancellation_reason = nil
  data.cancellation_time = nil
  self._queries[qid] = data
end

--- Returns an iterator function for the queries in the collection.
function Queries:pairs()
  return pairs(self._queries)
end

--- Deletes a query from the collection.
--- @param qid string # Query ID.
function Queries:delete(qid)
  self._queries[qid] = nil
end

--- Retrieves a query from the collection.
--- @param qid string # Query ID.
--- @return table|nil # Query data or nil if not found.
function Queries:get(qid)
  if not self._queries[qid] then
    logger.warning("Query with ID " .. tostring(qid) .. " not found.")
    return nil
  end
  return self._queries[qid]
end

--- Gets queries for a specific buffer.
--- @param buf number # The buffer number
--- @return table # List of query IDs for the buffer
function Queries:get_for_buffer(buf)
  local result = {}
  for qid, query_data in pairs(self._queries) do
    if query_data.buf == buf then
      table.insert(result, qid)
    end
  end
  return result
end

--- Marks a query as cancelled.
--- @param qid string # Query ID.
--- @param reason string|nil # Cancellation reason (optional)
function Queries:mark_cancelled(qid, reason)
  local query = self._queries[qid]
  if query then
    query.cancelled = true
    query.cancellation_reason = reason or "user"
    query.cancellation_time = os.time()
  end
end

--- Checks if a query was cancelled.
--- @param qid string # Query ID.
--- @return boolean # True if cancelled, false otherwise.
function Queries:is_cancelled(qid)
  local query = self._queries[qid]
  return query and query.cancelled or false
end

--- Cleans up old queries from the collection based on the specified criteria.
--- @param N number # Number of queries to keep.
--- @param age number # Age of queries to keep in seconds.
function Queries:cleanup(N, age)
  local current_time = os.time()

  local query_count = 0
  for _ in self:pairs() do
    query_count = query_count + 1
  end

  if query_count <= N then
    return
  end

  for qid, query_data in self:pairs() do
    if current_time - query_data.timestamp > age then
      self:delete(qid)
    end
  end
end

return Queries
