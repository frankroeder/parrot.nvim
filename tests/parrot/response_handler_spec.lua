local ResponseHandler = require("parrot.response_handler")
local stub = require("luassert.stub")

describe("ResponseHandler", function()
  local mock_utils, mock_queries
  local original_vim_api = {}

  before_each(function()
    -- Store original vim API functions
    original_vim_api.nvim_get_current_buf = vim.api.nvim_get_current_buf
    original_vim_api.nvim_get_current_win = vim.api.nvim_get_current_win
    original_vim_api.nvim_create_namespace = vim.api.nvim_create_namespace
    original_vim_api.nvim_buf_set_extmark = vim.api.nvim_buf_set_extmark
    original_vim_api.nvim_buf_is_valid = vim.api.nvim_buf_is_valid
    original_vim_api.nvim_buf_get_extmark_by_id = vim.api.nvim_buf_get_extmark_by_id
    original_vim_api.nvim_buf_set_lines = vim.api.nvim_buf_set_lines
    original_vim_api.nvim_win_get_cursor = vim.api.nvim_win_get_cursor
    original_vim_api.vim_split = vim.split

    -- Mock vim API functions
    vim.api.nvim_get_current_buf = stub.new().returns(1)
    vim.api.nvim_get_current_win = stub.new().returns(1)
    vim.api.nvim_create_namespace = stub.new().returns(1)
    vim.api.nvim_buf_set_extmark = stub.new().returns(1)
    vim.api.nvim_buf_is_valid = stub.new().returns(true)
    vim.api.nvim_buf_get_extmark_by_id = stub.new().returns({ 1 })
    vim.api.nvim_buf_set_lines = stub.new()
    vim.api.nvim_win_get_cursor = stub.new().returns({ 1, 0 })
    vim.split = stub.new().returns({ "test" })

    mock_utils = {
      uuid = stub.new().returns("test-uuid"),
      undojoin = stub.new(),
      cursor_to_line = stub.new(),
    }

    mock_queries = {
      get = stub.new().returns({ ns_id = 1, ex_id = 1 }),
    }

    package.loaded["parrot.utils"] = mock_utils
  end)

  after_each(function()
    -- Restore original vim API functions
    vim.api.nvim_get_current_buf = original_vim_api.nvim_get_current_buf
    vim.api.nvim_get_current_win = original_vim_api.nvim_get_current_win
    vim.api.nvim_create_namespace = original_vim_api.nvim_create_namespace
    vim.api.nvim_buf_set_extmark = original_vim_api.nvim_buf_set_extmark
    vim.api.nvim_buf_is_valid = original_vim_api.nvim_buf_is_valid
    vim.api.nvim_buf_get_extmark_by_id = original_vim_api.nvim_buf_get_extmark_by_id
    vim.api.nvim_buf_set_lines = original_vim_api.nvim_buf_set_lines
    vim.api.nvim_win_get_cursor = original_vim_api.nvim_win_get_cursor
    vim.split = original_vim_api.vim_split

    package.loaded["parrot.utils"] = nil
  end)

  it("should create a new ResponseHandler with default values", function()
    local handler = ResponseHandler:new(mock_queries)
    assert.are.same(1, handler.buffer)
    assert.are.same(vim.api.nvim_get_current_win(), handler.window)
    assert.are.same("", handler.prefix)
    assert.are.same(false, handler.cursor)
    assert.are.same(0, handler.first_line)
    assert.are.same(0, handler.finished_lines)
    assert.are.same("", handler.response)
    assert.are.same(mock_queries, handler.queries)
  end)

  it("should create a new ResponseHandler with custom values", function()
    local handler = ResponseHandler:new(mock_queries, nil, 3, 4, true, "prefix", true)
    assert.are.same(1, handler.buffer)
    assert.are.same(3, handler.window)
    assert.are.same("prefix", handler.prefix)
    assert.are.same(true, handler.cursor)
    assert.are.same(4, handler.first_line)
    assert.are.same(0, handler.finished_lines)
    assert.are.same("", handler.response)
    assert.are.same(mock_queries, handler.queries)
  end)

  it("should handle a chunk of response", function()
    local handler = ResponseHandler:new(mock_queries)
    handler:handle_chunk(1, "test chunk")
    assert.are.same("test chunk", handler.response)
    -- assert.stub(mock_vim.api.nvim_buf_set_lines).was_called()
    -- assert.stub(mock_vim.api.nvim_buf_set_extmark).was_called()
  end)

  it("should not process if buffer is invalid", function()
    vim.api.nvim_buf_is_valid.returns(false)
    local handler = ResponseHandler:new(mock_queries)
    handler:handle_chunk(1, nil)
    assert.are.same("", handler.response)
  end)

  it("should update the response with a new chunk", function()
    local handler = ResponseHandler:new(mock_queries)
    handler:update_response("test chunk")
    handler:update_response(" test chunk")
    assert.are.same("test chunk test chunk", handler.response)
  end)

  it("should not move the cursor when cursor is false", function()
    local handler = ResponseHandler:new(mock_queries)
    handler.response = "line1\nline2"
    handler:move_cursor()
    assert.stub(mock_utils.cursor_to_line).was_not_called()
  end)

  it("should create a handler function", function()
    local handler = ResponseHandler:new(mock_queries)
    local handler_func = handler:create_handler()
    assert.is_function(handler_func)
  end)
end)
