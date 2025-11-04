local Pool = require("parrot.pool")
local Queries = require("parrot.queries")

describe("Cancellation functionality", function()
  describe("Pool", function()
    local pool

    before_each(function()
      pool = Pool:new()
    end)

    it("should add process with qid and target_type", function()
      local mock_job = { handle = {}, pid = 123 }
      pool:add(mock_job, 1, "test-qid-1", "chat")

      assert.equals(1, #pool._processes)
      assert.equals("test-qid-1", pool._processes[1].qid)
      assert.equals("chat", pool._processes[1].target_type)
      assert.equals(1, pool._processes[1].buf)
    end)

    it("should get processes for buffer", function()
      local job1 = { handle = {}, pid = 123 }
      local job2 = { handle = {}, pid = 124 }
      local job3 = { handle = {}, pid = 125 }

      pool:add(job1, 1, "qid-1", "chat")
      pool:add(job2, 2, "qid-2", "rewrite")
      pool:add(job3, 1, "qid-3", "append")

      local buf1_processes = pool:get_for_buffer(1)
      assert.equals(2, #buf1_processes)
      assert.equals("qid-1", buf1_processes[1].qid)
      assert.equals("qid-3", buf1_processes[2].qid)
    end)

    it("should get most recent active job", function()
      local job1 = { handle = {}, pid = 123 }
      local job2 = { handle = {}, pid = 124 }

      -- Manually set different timestamps to ensure predictable test
      pool:add(job1, 1, "qid-1", "chat")
      pool._processes[1].timestamp = os.time() - 10  -- Older timestamp

      pool:add(job2, 2, "qid-2", "rewrite")
      pool._processes[2].timestamp = os.time()  -- Newer timestamp

      local active = pool:get_active_job()
      assert.equals("qid-2", active.qid)
    end)

    it("should check if pool has active jobs", function()
      assert.is_false(pool:has_active_jobs())

      local job1 = { handle = {}, pid = 123 }
      pool:add(job1, 1, "qid-1", "chat")

      assert.is_true(pool:has_active_jobs())
    end)
  end)

  describe("Queries", function()
    local queries

    before_each(function()
      queries = Queries:new()
    end)

    it("should initialize cancellation state when adding query", function()
      queries:add("test-qid", { buf = 1, provider = "test" })

      local query = queries:get("test-qid")
      assert.is_false(query.cancelled)
      assert.is_nil(query.cancellation_reason)
      assert.is_nil(query.cancellation_time)
    end)

    it("should mark query as cancelled", function()
      queries:add("test-qid", { buf = 1, provider = "test" })
      queries:mark_cancelled("test-qid", "user")

      local query = queries:get("test-qid")
      assert.is_true(query.cancelled)
      assert.equals("user", query.cancellation_reason)
      assert.is_not_nil(query.cancellation_time)
    end)

    it("should check if query is cancelled", function()
      queries:add("test-qid", { buf = 1, provider = "test" })

      assert.is_false(queries:is_cancelled("test-qid"))

      queries:mark_cancelled("test-qid")

      assert.is_true(queries:is_cancelled("test-qid"))
    end)

    it("should get queries for buffer", function()
      queries:add("qid-1", { buf = 1, provider = "test" })
      queries:add("qid-2", { buf = 2, provider = "test" })
      queries:add("qid-3", { buf = 1, provider = "test" })

      local buf1_queries = queries:get_for_buffer(1)
      assert.equals(2, #buf1_queries)
    end)

    it("should handle cancellation for non-existent query gracefully", function()
      -- Should not error
      queries:mark_cancelled("non-existent-qid")
      assert.is_false(queries:is_cancelled("non-existent-qid"))
    end)
  end)

  describe("Integration: Pool and Queries", function()
    local pool, queries

    before_each(function()
      pool = Pool:new()
      queries = Queries:new()
    end)

    it("should link pool processes with queries via qid", function()
      -- Add a query
      queries:add("qid-1", { buf = 1, provider = "test" })

      -- Add corresponding process
      local job1 = { handle = {}, pid = 123 }
      pool:add(job1, 1, "qid-1", "chat")

      -- Verify linkage
      local process = pool._processes[1]
      assert.equals("qid-1", process.qid)

      local query = queries:get("qid-1")
      assert.is_not_nil(query)
      assert.is_false(query.cancelled)
    end)

    it("should maintain cancellation state when marking queries", function()
      -- Setup query and process
      queries:add("qid-1", { buf = 1, provider = "test" })
      local job1 = { handle = {}, pid = 123 }
      pool:add(job1, 1, "qid-1", "chat")

      -- Mark query as cancelled
      queries:mark_cancelled("qid-1", "user")

      -- Verify cancellation state
      assert.is_true(queries:is_cancelled("qid-1"))
      local query = queries:get("qid-1")
      assert.equals("user", query.cancellation_reason)

      -- Process should still exist in pool (until explicitly removed)
      assert.equals(1, #pool._processes)
    end)

    it("should support buffer-specific cancellation", function()
      -- Setup multiple queries and processes for different buffers
      queries:add("qid-1", { buf = 1, provider = "test" })
      queries:add("qid-2", { buf = 1, provider = "test" })
      queries:add("qid-3", { buf = 2, provider = "test" })

      local job1 = { handle = {}, pid = 123 }
      local job2 = { handle = {}, pid = 124 }
      local job3 = { handle = {}, pid = 125 }

      pool:add(job1, 1, "qid-1", "chat")
      pool:add(job2, 1, "qid-2", "append")
      pool:add(job3, 2, "qid-3", "rewrite")

      -- Get buffer-specific queries and processes
      local buf1_queries = queries:get_for_buffer(1)
      local buf1_processes = pool:get_for_buffer(1)

      assert.equals(2, #buf1_queries)
      assert.equals(2, #buf1_processes)

      -- Mark buffer 1 queries as cancelled
      for _, qid in ipairs(buf1_queries) do
        queries:mark_cancelled(qid, "buffer_stop")
      end

      -- Verify only buffer 1 queries are cancelled
      assert.is_true(queries:is_cancelled("qid-1"))
      assert.is_true(queries:is_cancelled("qid-2"))
      assert.is_false(queries:is_cancelled("qid-3"))
    end)

    it("should handle multiple target types correctly", function()
      -- Add queries for different target types
      queries:add("chat-qid", { buf = 1, provider = "test" })
      queries:add("rewrite-qid", { buf = 1, provider = "test" })
      queries:add("append-qid", { buf = 1, provider = "test" })

      local job1 = { handle = {}, pid = 123 }
      local job2 = { handle = {}, pid = 124 }
      local job3 = { handle = {}, pid = 125 }

      pool:add(job1, 1, "chat-qid", "chat")
      pool:add(job2, 1, "rewrite-qid", "rewrite")
      pool:add(job3, 1, "append-qid", "append")

      -- Verify all have correct target types
      assert.equals("chat", pool._processes[1].target_type)
      assert.equals("rewrite", pool._processes[2].target_type)
      assert.equals("append", pool._processes[3].target_type)
    end)

    it("should preserve query data when marking as cancelled", function()
      -- Add query with some data
      queries:add("qid-1", {
        buf = 1,
        provider = "test",
        model = "test-model",
        ns_id = 100,
        custom_field = "custom_value"
      })

      -- Mark as cancelled
      queries:mark_cancelled("qid-1", "test_reason")

      -- Verify original data is preserved
      local query = queries:get("qid-1")
      assert.equals(1, query.buf)
      assert.equals("test", query.provider)
      assert.equals("test-model", query.model)
      assert.equals(100, query.ns_id)
      assert.equals("custom_value", query.custom_field)

      -- And cancellation fields are added
      assert.is_true(query.cancelled)
      assert.equals("test_reason", query.cancellation_reason)
      assert.is_not_nil(query.cancellation_time)
    end)
  end)
end)
