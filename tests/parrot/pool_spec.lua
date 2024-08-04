local Pool = require("parrot.pool")

describe("Pool", function()
  describe("new", function()
    it("should create a new pool", function()
      local pool = Pool:new()
      assert.are.same({}, pool._processes)
    end)
  end)

  describe("add", function()
    it("should add a process to the pool", function()
      local pool = Pool:new()
      local job = { pid = 1 }
      local buf = 10
      pool:add(job, buf)
      assert.are.same({ { job = job, buf = buf } }, pool._processes)
    end)
  end)

  describe("unique_for_buffer", function()
    it("should return true for nil buffer", function()
      local pool = Pool:new()
      assert.is_true(pool:unique_for_buffer(nil))
    end)

    it("should return true for unique buffer", function()
      local pool = Pool:new()
      pool:add({ pid = 1 }, 10)
      assert.is_true(pool:unique_for_buffer(20))
    end)

    it("should return false for non-unique buffer", function()
      local pool = Pool:new()
      pool:add({ pid = 1 }, 10)
      assert.is_false(pool:unique_for_buffer(10))
    end)
  end)

  describe("remove", function()
    it("should remove a process from the pool", function()
      local pool = Pool:new()
      local job1 = { pid = 1 }
      local job2 = { pid = 2 }
      pool:add(job1, 10)
      pool:add(job2, 20)
      pool:remove(1)
      assert.are.same({ { job = job2, buf = 20 } }, pool._processes)
    end)
  end)

  describe("is_empty", function()
    it("should return true for empty pool", function()
      local pool = Pool:new()
      assert.is_true(pool:is_empty())
    end)

    it("should return false for non-empty pool", function()
      local pool = Pool:new()
      pool:add({ pid = 1 }, 10)
      assert.is_false(pool:is_empty())
    end)
  end)

  describe("ipairs", function()
    it("should return an iterator for the processes", function()
      local pool = Pool:new()
      pool:add({ pid = 1 }, 10)
      pool:add({ pid = 2 }, 20)
      local result = {}
      for _, process in pool:ipairs() do
        table.insert(result, process.job.pid)
      end
      assert.are.same({ 1, 2 }, result)
    end)
  end)
end)
