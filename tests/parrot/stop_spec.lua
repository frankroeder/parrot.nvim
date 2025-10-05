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

      pool:add(job1, 1, "qid-1", "chat")
      -- Small delay to ensure different timestamps
      os.execute("sleep 0.01")
      pool:add(job2, 2, "qid-2", "rewrite")

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
end)
