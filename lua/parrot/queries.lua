local logger = require("parrot.logger")

local Queries = {}
Queries.__index = Queries

--- Creates a new Queries instance.
--- @return table # A new Queries instance.
function Queries:new()
  return setmetatable({ _queries = {} }, self)
end

--- Adds a query to the collection.
--- @param qid number # Query ID.
--- @param data table # Query data.
function Queries:add(qid, data)
  self._queries[qid] = data
end

--- Returns an iterator function for the queries in the collection.
--- @return function # An iterator function for the queries.
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
