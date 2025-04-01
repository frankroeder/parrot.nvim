local utils = require("parrot.utils")
local futils = require("parrot.file_utils")
local pft = require("plenary.filetype")
local logger = require("parrot.logger")
local M = {}

-- Splits a command string by literal colons.
function M.cmd_split(cmd)
  return vim.split(cmd, ":", { plain = true })
end

-- Given a message string, only lines that start (after optional whitespace)
-- with "@file:" or "@buffer:" are treated as commands.
function M.insert_contexts(msg)
  if not msg or type(msg) ~= "string" then
    logger.error("Invalid message for context insertion: " .. tostring(msg))
    return ""
  end
  local show_hints = false

  local loaded_config = require("parrot.config")
  if loaded_config.loaded then
    show_hints = loaded_config.options.show_context_hints
  end

  -- Split message into lines.
  local lines = vim.split(msg, "\n", { plain = true })
  local normal_lines = {}
  local contexts = {}

  local function add_file_context(filepath, source_info)
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
        logger.warning("Failed to read file or file is empty: " .. filepath)
      end
    else
      logger.warning("File not readable: " .. filepath)
    end
  end

  for _, line in ipairs(lines) do
    -- Check for commands at beginning of the line.
    local file_cmd = line:match("^%s*@file:(.+)$")
    local buffer_cmd = line:match("^%s*@buffer:(%S+)$")
    local dir_cmd = line:match("^%s*@directory:(.+)$")

    if file_cmd then
      local path_arg = file_cmd
      if path_arg:sub(1, 1) == '"' and path_arg:sub(-1) == '"' then
        path_arg = path_arg:sub(2, -2)
      end

      local is_glob = path_arg:find("*", 1, true)

      local pattern_or_path
      if path_arg:match("^[/~]") or path_arg:match("^%a:[/\\]") then
        pattern_or_path = vim.fn.expand(path_arg)
      else
        local cwd = vim.fn.getcwd()
        pattern_or_path = utils.path_join(cwd, path_arg)
      end

      if is_glob then
        local files = vim.fn.glob(pattern_or_path, true, true)
        if #files > 0 then
          for _, filepath in ipairs(files) do
            add_file_context(filepath, "@file (glob)")
          end
        else
          logger.warning("Glob pattern yielded no files: " .. pattern_or_path)
        end
      else
        add_file_context(pattern_or_path, "@file")
      end
    elseif buffer_cmd then
      local buf_nr
      if type(buffer_cmd) == "number" then
        buf_nr = buffer_cmd
      else
        buf_nr = vim.fn.bufnr(buffer_cmd)
      end
      if buf_nr ~= -1 and vim.api.nvim_buf_is_loaded(buf_nr) then
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
          logger.warning("Failed to read buffer: " .. buffer_cmd)
        end
      else
        logger.warning("Buffer not loaded or found: " .. buffer_cmd)
      end
    elseif dir_cmd then
      local path = dir_cmd
      if path:sub(1, 1) == '"' and path:sub(-1) == '"' then
        path = path:sub(2, -2)
      end
      local dir_path = vim.fn.expand(path)
      if vim.fn.isdirectory(dir_path) == 1 then
        local files = vim.fn.glob(dir_path .. "/*", true, true)
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
              logger.warning("Failed to read file in directory: " .. file)
            end
          end
        end
      else
        logger.warning("Directory not found: " .. dir_path)
      end
    else
      -- Regular line, include in the message.
      table.insert(normal_lines, line)
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
    -- Ensure content isn't just whitespace
    if ctx.content and ctx.content:match("%S") then
      -- Use full name/path as header
      local code_block_header = ctx.name
      local code_block_content
      if ctx.filetype and ctx.filetype ~= "" then
        code_block_content = "```" .. ctx.filetype .. "\n" .. ctx.content .. "\n```"
      else
        code_block_content = "```\n" .. ctx.content .. "\n```"
      end
      table.insert(result_parts, "\n\n" .. code_block_header .. "\n" .. code_block_content)
    end
  end
  return table.concat(result_parts, "")
end

return M
