-- local mock = require('luassert.mock')
-- local async = require("plenary.async")

-- describe("completion.blink", function()
--   local blink_async_mock

--   before_each(function()
--     -- Create a stub for the async lib from blink
--     _G.blink = {
--       cmp = {
--         lib = {
--           async = {
--             task = {
--               new = function(fn)
--                 return {
--                   map = function(self, mapper)
--                     return self
--                   end,
--                   catch = function(self, catcher)
--                     return self
--                   end
--                 }
--               end,
--               await_all = function(tasks)
--                 return {
--                   map = function(self, mapper)
--                     return self
--                   end
--                 }
--               end
--             }
--           }
--         },
--         types = {
--           CompletionItemKind = {
--             Keyword = 1,
--             Folder = 2,
--             File = 3,
--             Buffer = 4
--           }
--         }
--       }
--     }

--     package.loaded["blink.cmp.lib.async"] = _G.blink.cmp.lib.async
--     package.loaded["blink.cmp.types"] = _G.blink.cmp.types
--   end)

--   after_each(function()
--     package.loaded["parrot.completion.blink"] = nil
--     package.loaded["blink.cmp.lib.async"] = nil
--     package.loaded["blink.cmp.types"] = nil
--     _G.blink = nil
--   end)

--   describe("Blink source", function()
--     it("should create a new source with default options", function()
--       local blink = require("parrot.completion.blink")
--       local source = blink.new()

--       assert.is_table(source.opts)
--       assert.is_false(source.opts.show_hidden_files)
--       assert.are.equal(50, source.opts.max_items)
--     end)

--     it("should return @ as trigger character", function()
--       local blink = require("parrot.completion.blink")
--       local source = blink.new()

--       assert.are.same({ "@" }, source:get_trigger_characters())
--     end)
--   end)
-- end)
