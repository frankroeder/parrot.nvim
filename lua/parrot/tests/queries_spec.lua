local Queries = require("parrot.queries")

describe("Queries", function()
  local queries

  before_each(function()
    queries = Queries:new()
  end)

  describe("add and get", function()
    it("should add and retrieve a query", function()
      local query_data = { content = "Test query", timestamp = os.time() }
      queries:add(1, query_data)
      assert.are.same(query_data, queries:get(1))
    end)

    it("should return nil for non-existent query", function()
      assert.is_nil(queries:get(999))
    end)
  end)

  describe("delete", function()
    it("should delete a query", function()
      queries:add(1, { content = "Test query" })
      queries:delete(1)
      assert.is_nil(queries:get(1))
    end)
  end)

  describe("pairs", function()
    it("should iterate over all queries", function()
      queries:add(1, { content = "Query 1" })
      queries:add(2, { content = "Query 2" })

      local count = 0
      for _, query in queries:pairs() do
        count = count + 1
        assert.is_not_nil(query.content)
      end
      assert.equals(2, count)
    end)
  end)

  describe("cleanup", function()
    it("should remove old queries", function()
      local current_time = os.time()
      queries:add(1, { content = "Old query", timestamp = current_time - 100 })
      queries:add(2, { content = "New query", timestamp = current_time })

      queries:cleanup(1, 50)

      assert.is_nil(queries:get(1))
      assert.is_not_nil(queries:get(2))
    end)

    it("should keep N most recent queries", function()
      local current_time = os.time()
      for i = 1, 5 do
        queries:add(i, { content = "Query " .. i, timestamp = current_time - i })
      end

      queries:cleanup(3, 3)

      local count = 0
      for _ in queries:pairs() do
        count = count + 1
      end
      assert.equals(3, count)
    end)
  end)
end)
