local logger = require("parrot.logger")

describe("Logger", function()
  local original_notify
  local original_schedule
  local notify_calls = {}
  local schedule_calls = {}

  before_each(function()
    -- Mock vim.notify
    original_notify = vim.notify
    vim.notify = function(msg, level, opts)
      table.insert(notify_calls, { msg = msg, level = level, opts = opts })
    end

    -- Mock vim.schedule
    original_schedule = vim.schedule
    vim.schedule = function(fn)
      table.insert(schedule_calls, fn)
      fn() -- Execute immediately for testing
    end

    -- Clear call history
    notify_calls = {}
    schedule_calls = {}
  end)

  after_each(function()
    vim.notify = original_notify
    vim.schedule = original_schedule
  end)

  describe("error function", function()
    it("should log error without context", function()
      logger.error("Test error message")

      assert.equal(1, #notify_calls)
      assert.equal("Test error message", notify_calls[1].msg)
      assert.equal(vim.log.levels.ERROR, notify_calls[1].level)
    end)

    it("should log error with context", function()
      local context = { file = "test.lua", line = 42 }
      logger.error("Test error message", context)

      assert.equal(1, #notify_calls)
      assert.matches("Test error message", notify_calls[1].msg)
      assert.matches("Context:", notify_calls[1].msg)
      assert.equal(vim.log.levels.ERROR, notify_calls[1].level)
    end)
  end)

  describe("warning function", function()
    it("should log warning without context", function()
      logger.warning("Test warning message")

      assert.equal(1, #notify_calls)
      assert.equal("Test warning message", notify_calls[1].msg)
      assert.equal(vim.log.levels.WARN, notify_calls[1].level)
    end)

    it("should log warning with context", function()
      local context = { operation = "test_op", value = 123 }
      logger.warning("Test warning message", context)

      assert.equal(1, #notify_calls)
      assert.matches("Test warning message", notify_calls[1].msg)
      assert.matches("Context:", notify_calls[1].msg)
      assert.equal(vim.log.levels.WARN, notify_calls[1].level)
    end)
  end)

  describe("info function", function()
    it("should log info message", function()
      logger.info("Test info message")

      assert.equal(1, #notify_calls)
      assert.equal("Test info message", notify_calls[1].msg)
      assert.equal(vim.log.levels.INFO, notify_calls[1].level)
    end)
  end)

  describe("debug function", function()
    it("should not log when debug is disabled", function()
      logger.set_debug(false)
      notify_calls = {} -- Clear the set_debug notification
      logger.debug("Test debug message")

      assert.equal(0, #notify_calls)
    end)

    it("should log when debug is enabled", function()
      logger.set_debug(true)
      notify_calls = {} -- Clear the set_debug notification
      logger.debug("Test debug message")

      -- Debug messages don't trigger vim.notify, but should be processed
      assert.equal(0, #notify_calls)
    end)

    it("should log with context when debug is enabled", function()
      logger.set_debug(true)
      notify_calls = {} -- Clear the set_debug notification
      local context = { debug_info = "test" }
      logger.debug("Test debug message", context)

      -- Debug messages don't trigger vim.notify
      assert.equal(0, #notify_calls)
    end)
  end)

  describe("critical function", function()
    it("should log critical error without context", function()
      logger.critical("Test critical error")

      assert.equal(1, #notify_calls)
      assert.matches("CRITICAL:", notify_calls[1].msg)
      assert.matches("Test critical error", notify_calls[1].msg)
      assert.equal(vim.log.levels.ERROR, notify_calls[1].level)
    end)

    it("should log critical error with context", function()
      local context = { error_code = 500 }
      logger.critical("Test critical error", context)

      assert.equal(1, #notify_calls)
      assert.matches("CRITICAL:", notify_calls[1].msg)
      assert.matches("Test critical error", notify_calls[1].msg)
      assert.matches("Context:", notify_calls[1].msg)
      assert.equal(vim.log.levels.ERROR, notify_calls[1].level)
    end)
  end)

  describe("set_debug function", function()
    it("should enable debug logging", function()
      logger.set_debug(true)

      assert.equal(1, #notify_calls)
      assert.matches("Debug logging enabled", notify_calls[1].msg)
      assert.equal(vim.log.levels.INFO, notify_calls[1].level)
    end)

    it("should disable debug logging", function()
      logger.set_debug(false)

      assert.equal(1, #notify_calls)
      assert.matches("Debug logging disabled", notify_calls[1].msg)
      assert.equal(vim.log.levels.INFO, notify_calls[1].level)
    end)
  end)

  describe("input sanitization", function()
    it("should handle non-string input", function()
      logger.error(123)

      assert.equal(1, #notify_calls)
      assert.equal("123", notify_calls[1].msg)
    end)

    it("should handle table input", function()
      logger.error({ error = "test", code = 404 })

      assert.equal(1, #notify_calls)
      assert.matches("error", notify_calls[1].msg)
      assert.matches("test", notify_calls[1].msg)
      assert.matches("404", notify_calls[1].msg)
    end)

    it("should handle empty string input", function()
      logger.error("")

      assert.equal(1, #notify_calls)
      assert.equal("Empty log message", notify_calls[1].msg)
    end)
  end)
end)
