local M = {}
M.nsId = nil

---@param color integer
---@return number[]
local function color_to_rgb(color)
	local r = bit.band(bit.rshift(color, 16), 0xff)
	local g = bit.band(bit.rshift(color, 8), 0xff)
	local b = bit.band(color, 0xff)
	return { r, g, b }
end

---@param group string
---@return nil|integer
local function get_hl_foreground(group)
	if vim.fn.has("nvim-0.9") == 1 then
		return vim.api.nvim_get_hl(0, { name = group }).fg
	else
		---@diagnostic disable-next-line: undefined-field
		return vim.api.nvim_get_hl_by_name(group, true).foreground
	end
end

local function get_random_rgb()
	return { math.random(100, 255), math.random(100, 255), math.random(100, 255) }
end

---@param recency float
---@return nil|number[]
local function get_scheme_color(recency)
	local hl_color = get_hl_foreground("Function")
	if hl_color == nil then
		return nil
	end
	local color = color_to_rgb(hl_color)
	--- NOTE: ^ taken from https://github.com/stevearc/overseer.nvim/blob/d8c5be15ff0f7ccecbaa8f3612a6764b22fc07ff/lua/overseer/util.lua#L493-L546

	local max_rgb_value = nil
	for _, value in ipairs(color) do
		max_rgb_value = max_rgb_value and math.max(max_rgb_value, value) or value
	end

	local scale_max = math.min(255 / max_rgb_value, 255)
	local scale_min = 0.5
	for i, value in ipairs(color) do
		color[i] = value * ((scale_max - scale_min) * recency + scale_min)
	end

	return color
end

---@param recency float
---@return string
local function get_color_str(recency)
	local c = get_scheme_color(recency) or get_random_rgb()
	return string.format("#%02X%02X%02X", unpack(c))
end

local function find_min_max_commit_times(parsed_lines)
	local min_time = nil
	local max_time = nil

	for _, value in ipairs(parsed_lines) do
		local time = tonumber(value["committer-time"])
		if time then
			min_time = min_time and math.min(min_time, time) or time
			max_time = max_time and math.max(max_time, time) or time
		end
	end

	return min_time, max_time
end

---Creates the highlights for Hash, NotCommited and random color per one hash
---@param parsed_lines any
M.map_highlights_per_hash = function(parsed_lines)
	vim.cmd([[
    highlight DimHashBlame guifg=DimGray
    highlight NotCommitedBlame guifg=bg guibg=bg
  ]])

	local min_time, max_time = find_min_max_commit_times(parsed_lines)
	for _, value in ipairs(parsed_lines) do
		local full_hash = value["hash"]
		local hash = string.sub(full_hash, 0, 8)
		if vim.fn.hlID(hash) == 0 then
			local recency = (tonumber(value["committer-time"]) - min_time) / (max_time - min_time)
			vim.cmd("highlight " .. hash .. " guifg=" .. get_color_str(recency))
		end
	end
end

---Applies the created highlights to a specified buffer
---@param buffId integer
---@param merge_consecutive boolean
M.highlight_same_hash = function(buffId, merge_consecutive)
	M.nsId = vim.api.nvim_create_namespace("blame_ns")
	local lines = vim.api.nvim_buf_get_lines(buffId, 0, -1, false)

	for idx, line in ipairs(lines) do
		local hash = line:match("^%S+")
		local should_skip = false
		if idx > 1 and merge_consecutive then
			should_skip = lines[idx - 1]:match("^%S+") == hash
		end
		if hash == "00000000" or should_skip then
			vim.api.nvim_buf_add_highlight(buffId, M.nsId, "NotCommitedBlame", idx - 1, 0, -1)
		else
			vim.api.nvim_buf_add_highlight(buffId, M.nsId, "DimHashBlame", idx - 1, 0, 8)
			vim.api.nvim_buf_add_highlight(buffId, M.nsId, hash, idx - 1, 9, -1)
		end
	end
end

return M
