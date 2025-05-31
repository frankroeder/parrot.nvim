local utils = require("parrot.utils")
local futils = require("parrot.file_utils")
local pft = require("plenary.filetype")
local logger = require("parrot.logger")
local M = {}

-- Splits a command string by literal colons.
function M.cmd_split(cmd)
  if type(cmd) ~= "string" then
    logger.warning("cmd_split: expected string input", { cmd = cmd, type = type(cmd) })
    return {}
  end
  return vim.split(cmd, ":", { plain = true })
end

-- Given a message string, only lines that start (after optional whitespace)
-- with "@file:" or "@buffer:" are treated as commands.
function M.insert_contexts(msg)
  if not msg then
    logger.warning("insert_contexts: received nil message")
    return ""
  end

  if type(msg) ~= "string" then
    logger.error("Invalid message for context insertion", {
      msg = msg,
      type = type(msg),
      expected = "string",
    })
    return ""
  end

  if msg == "" then
    return ""
  end

  local show_hints = false

  local ok, loaded_config = pcall(require, "parrot.config")
  if ok and loaded_config and loaded_config.loaded then
    show_hints = loaded_config.options.show_context_hints
  end

  -- Split message into lines.
  local lines = vim.split(msg, "\n", { plain = true })
  local normal_lines = {}
  local contexts = {}

  local function add_file_context(filepath, source_info)
    if not filepath or type(filepath) ~= "string" or filepath == "" then
      logger.warning("add_file_context: invalid filepath", { filepath = filepath })
      return
    end

    if vim.fn.filereadable(filepath) == 1 then
      local ok, content = pcall(futils.read_file, filepath)
      if ok and content and content:match("%S") then
        local ft = pft.detect(filepath, {})
        if filepath:match("%.txt$") then
          ft = ""
        end
        content = content:gsub("\n+$", "")
        if show_hints then
          vim.notify("Attached context " .. source_info .. ": " .. vim.fs.basename(filepath))
        end
        table.insert(contexts, { content = content, filetype = ft, name = filepath })
      else
        logger.warning("Failed to read file or file is empty", {
          filepath = filepath,
          readable = vim.fn.filereadable(filepath) == 1,
        })
      end
    else
      logger.warning("File not readable", { filepath = filepath })
    end
  end

  for _, line in ipairs(lines) do
    if type(line) == "string" then
      -- Check for commands at beginning of the line.
      local file_cmd = line:match("^%s*@file:(.+)$")
      local buffer_cmd = line:match("^%s*@buffer:(%S+)$")
      local dir_cmd = line:match("^%s*@directory:(.+)$")

      if file_cmd then
        local path_arg = file_cmd
        if path_arg:sub(1, 1) == '"' and path_arg:sub(-1) == '"' then
          path_arg = path_arg:sub(2, -2)
        end

        local pattern_to_expand
        if path_arg:match("^[/~$]") or path_arg:match("^%a:[/\\]") then
          pattern_to_expand = path_arg
        else
          local cwd = vim.fn.getcwd()
          pattern_to_expand = utils.path_join(cwd, path_arg)
        end

        local ok, files = pcall(vim.fn.expand, pattern_to_expand, false, true)
        if ok and type(files) == "table" and #files > 0 then
          for _, filepath in ipairs(files) do
            if vim.fn.filereadable(filepath) == 1 then
              add_file_context(filepath, "@file")
            end
          end
        else
          logger.warning("Pattern yielded no files or failed expansion", {
            pattern = pattern_to_expand,
            error = not ok and files or nil,
          })
        end
      elseif buffer_cmd then
        local buf_nr
        if tonumber(buffer_cmd) then
          buf_nr = tonumber(buffer_cmd)
        else
          buf_nr = vim.fn.bufnr(buffer_cmd)
        end

        if buf_nr and buf_nr ~= -1 and vim.api.nvim_buf_is_valid(buf_nr) and vim.api.nvim_buf_is_loaded(buf_nr) then
          local ok, result = pcall(function()
            local ft = pft.detect(vim.api.nvim_buf_get_name(buf_nr), {})
            local buf_lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
            local name = vim.api.nvim_buf_get_name(buf_nr)
            if show_hints then
              vim.notify("Attached context @buffer: " .. vim.fs.basename(name))
            end
            return { content = table.concat(buf_lines, "\n"), filetype = ft, name = name }
          end)
          if ok and result then
            table.insert(contexts, result)
          else
            logger.warning("Failed to read buffer", {
              buffer_cmd = buffer_cmd,
              buf_nr = buf_nr,
              error = result,
            })
          end
        else
          logger.warning("Buffer not valid, loaded, or found", {
            buffer_cmd = buffer_cmd,
            buf_nr = buf_nr,
            valid = buf_nr and vim.api.nvim_buf_is_valid(buf_nr),
            loaded = buf_nr and vim.api.nvim_buf_is_loaded(buf_nr),
          })
        end
      elseif dir_cmd then
        local path = dir_cmd
        if path:sub(1, 1) == '"' and path:sub(-1) == '"' then
          path = path:sub(2, -2)
        end

        local ok_expand, dir_path = pcall(vim.fn.expand, path)
        if ok_expand then
          if vim.fn.isdirectory(dir_path) == 1 then
            local ok_glob, files = pcall(vim.fn.glob, dir_path .. "/*", true, true)
            if ok_glob and type(files) == "table" then
              for _, file in ipairs(files) do
                if vim.fn.filereadable(file) == 1 then
                  local ok, content = pcall(futils.read_file, file)
                  if ok and content and content:match("%S") then
                    local ft = pft.detect(file, {})
                    if file:match("%.txt$") then
                      ft = ""
                    end
                    content = content:gsub("\n+$", "")
                    if show_hints then
                      vim.notify(
                        "Attached context @directory: " .. vim.fs.basename(dir_path) .. " - " .. vim.fs.basename(file)
                      )
                    end
                    table.insert(contexts, { content = content, filetype = ft, name = file })
                  else
                    logger.debug("Failed to read file in directory", { file = file })
                  end
                end
              end
            else
              logger.warning("Failed to glob directory", {
                dir_path = dir_path,
                error = not ok_glob and files or nil,
              })
            end
          else
            logger.warning("Directory not found or not accessible", {
              dir_path = dir_path,
              exists = vim.fn.isdirectory(dir_path),
            })
          end
        else
          logger.warning("Failed to expand directory path", { path = path, error = dir_path })
        end
      else
        -- Regular line, include in the message.
        table.insert(normal_lines, line)
      end
    else
      logger.warning("insert_contexts: invalid line type", { line = line, type = type(line) })
    end
  end

  -- Reassemble the base message.
  local base = table.concat(normal_lines, "\n")
  base = base:gsub("[\n\r]+$", "")

  if #contexts == 0 then
    return base
  end

  -- Append each context as its own code block.
  local result_parts = { base } -- Start with the base message

  for _, ctx in ipairs(contexts) do
    -- Ensure context is valid and content isn't just whitespace
    if type(ctx) == "table" and ctx.content and type(ctx.content) == "string" and ctx.content:match("%S") then
      -- Use full name/path as header
      local code_block_header = ctx.name or "Unknown file"
      local code_block_content
      if ctx.filetype and ctx.filetype ~= "" then
        code_block_content = "```" .. ctx.filetype .. "\n" .. ctx.content .. "\n```"
      else
        code_block_content = "```\n" .. ctx.content .. "\n```"
      end
      table.insert(result_parts, "\n\n" .. code_block_header .. "\n" .. code_block_content)
    else
      logger.debug("Skipping invalid context", { ctx = ctx })
    end
  end
  return table.concat(result_parts, "")
end

return M
