-- local mock = require('luassert.mock')
-- local async = require("plenary.async")

-- describe("completion.cmp", function()
--   local cmp_mock
--   local subject

--   before_each(function()
--     -- Mock cmp
--     cmp_mock = mock(require('cmp'), true)
--     -- Load the source with mocked dependencies
--     subject = require("parrot.completion.cmp")
--   end)

--   after_each(function()
--     mock.revert(cmp_mock)
--     package.loaded["parrot.completion.cmp"] = nil
--   end)

--   describe("get_trigger_characters", function()
--     it("should return @ as trigger character", function()
--       local result = subject.get_trigger_characters()
--       assert.are.same({ "@" }, result)
--     end)
--   end)

--   describe("complete", function()
--     it("should handle empty request gracefully", function()
--       async.run(function()
--         local callback_called = false
--         local callback = function(result)
--           callback_called = true
--           assert.are.same({ items = {}, isIncomplete = false }, result)
--         end

--         subject.complete(subject, {}, callback)
--         assert.is_true(callback_called)
--       end)
--     end)

--     it("should handle @file: command", function()
--       async.run(function()
--         local request = {
--           context = { cursor_before_line = "@file:" },
--           offset = 6
--         }

--         local callback_called = false
--         local callback = function(result)
--           callback_called = true
--           assert.is_true(#result.items >= 0)
--           assert.is_true(type(result.isIncomplete) == "boolean")
--         end

--         subject.complete(subject, request, callback)
--         assert.is_true(callback_called)
--       end)
--     end)
--   end)
-- end)
