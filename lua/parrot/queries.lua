local logger = require("parrot.logger")

local Queries = {}
Queries.__index = Queries

function Queries:new()
  local o = {_queries = {}}
  setmetatable(o, self)
  self.__index = self
  return o
end

-- add a process to the pool
---@param qid number # query id
---@param data table # query data
function Queries:add(qid, data)
	self._queries[qid] = data
end

function Queries:pairs()
	return pairs(self._queries)
end

---@param qid string # query id
function Queries:delete(qid)
	self._queries[qid] = nil
end

---@param qid string # query id
---@return table | nil # query data
function Queries:get(qid)
	if not self._queries[qid] then
		logger.warning("Query with ID " .. tostring(qid) .. " not found.")
		return nil
  end
	return self._queries[qid]
end

---@param N number # number of queries to keep
---@param age number # age of queries to keep in seconds
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
