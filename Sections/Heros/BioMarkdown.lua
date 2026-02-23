local ADDON, ns = ...

local M = ns.HerosSection

function M.BuildBioMarkdown(ctx)
	local fn = ctx.fn

	local function Bio_EscapeMarkdownText(raw)
		local text = tostring(raw or "")
		text = text:gsub("|", "||")
		return text
	end

	local COLOR_H1 = "|cffffd100"
	local COLOR_H2 = "|cffffd100"
	local COLOR_H3 = "|cffffd100"
	local COLOR_BOLD = "|cffffd100"
	local COLOR_ITALIC = "|cff8aa3b8"
	local COLOR_GOLD = "|cffffd100"
	local COLOR_BLUE = "|cff0070dd"
	local COLOR_RED = "|cffff2020"
	local COLOR_GREEN = "|cff1eff00"
	local COLOR_PURPLE = "|cffa335ee"
	local COLOR_ORANGE = "|cffff8000"
	local COLOR_WHITE = "|cffffffff"
	local COLOR_GRAY = "|cff9d9d9d"
	local COLOR_LINK = "|cff00aaff"
	local COLOR_RESET = "|r"
	local H_SPACING = {
		[1] = 10,
		[2] = 8,
		[3] = 6,
	}
	local H_BEFORE = {
		[1] = 5,
		[2] = 5,
		[3] = 5,
	}
	local INDENT_2 = 12
	local INDENT_3 = 24
	local INDENT_4 = 36
	local TOOLTIP_LINK_ATLAS = "_AnimaChannel-Channel-Line-horizontal"
	local TOOLTIP_LINK_ATLAS_WIDTH = 64
	local TOOLTIP_LINK_ATLAS_HEIGHT = 8
	local TOOLTIP_LINK_ATLAS_OFFSET_X = 0
	local TOOLTIP_LINK_ATLAS_OFFSET_Y = 5

	local function ParseIndent(line)
		if line:match("^%s*%-%-%-%-%s+") then
			return INDENT_4, line:gsub("^%s*%-%-%-%-%s+", ""), true
		end
		if line:match("^%s*%-%-%-%s+") then
			return INDENT_3, line:gsub("^%s*%-%-%-%s+", ""), true
		end
		if line:match("^%s*%-%-%s+") then
			return INDENT_2, line:gsub("^%s*%-%-%s+", ""), true
		end
		return 0, line, false
	end

	local function IndentPrefix(indent)
		if not indent or indent <= 0 then
			return ""
		end
		local spaces = math.max(1, math.floor(indent / 4 + 0.5))
		return string.rep(" ", spaces)
	end

	local function AppendSpacing(out, px)
		if not px or px <= 0 then
			return
		end
		-- Approximate pixel spacing with empty lines (FontString can't vary line height per line).
		local lines = math.max(1, math.floor(px / 6 + 0.5))
		for _ = 1, lines do
			out[#out + 1] = ""
		end
	end

	local QUALITY_COLORS = {
		L1 = COLOR_GRAY,
		L2 = COLOR_WHITE,
		L3 = COLOR_GREEN,
		L4 = COLOR_BLUE,
		L5 = COLOR_PURPLE,
		L6 = COLOR_ORANGE,
	}

	local INDEX_COLORS = {
		["1"] = COLOR_BLUE,
		["2"] = COLOR_RED,
		["3"] = COLOR_GREEN,
		["4"] = COLOR_PURPLE,
		["5"] = COLOR_ORANGE,
	}

	local function ColorizeStarText(raw)
		local content = tostring(raw or "")
		content = content:gsub("^%s+", "")
		local level = content:match("^L(%d+)%s+")
		if level then
			local key = "L" .. level
			local color = QUALITY_COLORS[key] or COLOR_GOLD
			local label = content:gsub("^L%d+%s+", "")
			return color .. label .. COLOR_RESET
		end
		local idx = content:match("^(%d+)%s+")
		if idx then
			local color = INDEX_COLORS[idx] or COLOR_GOLD
			local label = content:gsub("^%d+%s+", "")
			return color .. label .. COLOR_RESET
		end
		return COLOR_GOLD .. content .. COLOR_RESET
	end

	local function StripStarToken(raw)
		local content = tostring(raw or "")
		content = content:gsub("^%s+", "")
		if content:match("^L%d+%s+") then
			return content:gsub("^L%d+%s+", "")
		end
		if content:match("^%d+%s+") then
			return content:gsub("^%d+%s+", "")
		end
		return content
	end

	local function TrimText(s)
		return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
	end

	local function IsAtlas(name)
		if ns and ns.Utils and ns.Utils.IsAtlas then
			return ns.Utils.IsAtlas(name)
		end
		return type(name) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
	end

	local function ParseTextureTarget(target)
		local raw = TrimText(target)
		local path, w, h = raw:match("^(.-)@(%d+)x(%d+)$")
		if not path then
			path = raw
		end
		local forcedAtlas = false
		local forcedTexture = false
		if path:sub(1, 6) == "atlas:" then
			path = path:sub(7)
			forcedAtlas = true
		elseif path:sub(1, 4) == "tex:" then
			path = path:sub(5)
			forcedTexture = true
		end
		path = TrimText(path)
		local nW = tonumber(w or "")
		local nH = tonumber(h or "")
		local isAtlas = (not forcedTexture) and (forcedAtlas or IsAtlas(path))
		return path, nW, nH, isAtlas
	end

	local function BuildTextureTag(path, w, h, isAtlas)
		local sizeW = tonumber(w or 32) or 32
		local sizeH = tonumber(h or sizeW) or sizeW
		if isAtlas then
			return string.format("|A:%s:%d:%d|a", path, sizeW, sizeH)
		end
		return string.format("|T%s:%d:%d|t", path, sizeW, sizeH)
	end

	local function ParseBraceTextureSpec(raw)
		local parts = {}
		for part in tostring(raw or ""):gmatch("([^;]+)") do
			parts[#parts + 1] = TrimText(part)
		end
		if #parts < 2 then
			return nil
		end
		local name = parts[1]
		local size = parts[2]
		if not name or name == "" or not size or size == "" then
			return nil
		end
		if name:match("^%d+$") then
			return nil
		end
		local w, h = size:match("^(%d+)%s*[xX]%s*(%d+)$")
		if not w then
			w = size:match("^(%d+)$")
		end
		if not w then
			return nil
		end
		local nW = tonumber(w)
		local nH = tonumber(h or w)
		if not nW then
			return nil
		end
		if nW < 10 then
			nW = 10
		elseif nW > 200 then
			nW = 200
		end
		if not nH or nH < 10 then
			nH = nW
		elseif nH > 200 then
			nH = 200
		end
		local title = parts[3]
		local body = parts[4]
		if title == "" then
			title = nil
		end
		if body == "" then
			body = nil
		end
		local path, _, _, isAtlas = ParseTextureTarget(name)
		if not path or path == "" then
			return nil
		end
		return path, nW, nH, isAtlas, title, body
	end

	local function RenderInline(text)
		text = Bio_EscapeMarkdownText(text)
		text = text:gsub("{([^}]+)}", function(spec)
			local path, w, h, isAtlas = ParseBraceTextureSpec(spec)
			if not path then
				return "{" .. spec .. "}"
			end
			return BuildTextureTag(path, w, h, isAtlas)
		end)
		text = text:gsub("!%[([^%]]*)%]%(([^%)]+)%)", function(alt, target)
			local path, w, h, isAtlas = ParseTextureTarget(target)
			if not path or path == "" then
				return alt or ""
			end
			local tag = BuildTextureTag(path, w, h, isAtlas)
			if alt and alt ~= "" then
				return tag .. " " .. alt
			end
			return tag
		end)
		text = text:gsub("%[(.-)%]%((.-)%)", function(label, url)
			local safeLabel = Bio_EscapeMarkdownText(label)
			local safeUrl = Bio_EscapeMarkdownText(url)
			if safeUrl ~= "" then
				return COLOR_LINK .. safeLabel .. COLOR_RESET .. " (" .. safeUrl .. ")"
			end
			return COLOR_LINK .. safeLabel .. COLOR_RESET
		end)
		text = text:gsub("%*%*(.-)%*%*", COLOR_BOLD .. "%1" .. COLOR_RESET)
		text = text:gsub("%*([^%*]+)%*", ColorizeStarText)
		return text
	end

	local function RenderInlinePlain(text)
		text = tostring(text or "")
		text = text:gsub("{([^}]+)}", function(spec)
			local path = ParseBraceTextureSpec(spec)
			if path then
				return ""
			end
			return "{" .. spec .. "}"
		end)
		text = text:gsub("!%[([^%]]*)%]%(([^%)]+)%)", "%1")
		text = text:gsub("%[(.-)%]%((.-)%)", function(label, url)
			if url and url ~= "" then
				return label .. " (" .. url .. ")"
			end
			return label
		end)
		text = text:gsub("%*%*(.-)%*%*", "%1")
		text = text:gsub("%*([^%*]+)%*", StripStarToken)
		return text
	end

	local function ParseIconSpec(raw)
		local parts = {}
		for part in tostring(raw or ""):gmatch("([^;]+)") do
			parts[#parts + 1] = TrimText(part)
		end
		if #parts < 2 or not parts[1]:match("^%d+$") or not parts[2]:match("^%d+$") then
			return nil
		end
		local id = parts[1]
		local nSize = tonumber(parts[2])
		if not nSize then
			return nil
		end
		if nSize < 10 then
			nSize = 10
		elseif nSize > 200 then
			nSize = 200
		end
		local title = parts[3]
		local body = parts[4]
		if title == "" then
			title = nil
		end
		if body == "" then
			body = nil
		end
		return tostring(id), nSize, title, body
	end

	local function ParseTooltipText(raw)
		local text = tostring(raw or "")
		local pos = text:find(";", 1, true)
		if pos then
			local title = TrimText(text:sub(1, pos - 1))
			local body = TrimText(text:sub(pos + 1))
			if title == "" then
				title = nil
			end
			if body == "" then
				body = nil
			end
			return title, body
		end
		text = TrimText(text)
		if text == "" then
			return nil, nil
		end
		return nil, text
	end

	local function SplitTooltipSegments(raw)
		local out = {}
		local i = 1
		local len = #raw
		while i <= len do
			local s, e, tip = raw:find("{(.-)}", i)
			if not s then
				local tail = raw:sub(i)
				if tail ~= "" then
					out[#out + 1] = { text = tail }
				end
				break
			end
			if s > i then
				out[#out + 1] = { text = raw:sub(i, s - 1) }
			end
			local nextS = raw:find("{", e + 1, true)
			local segmentText = nextS and raw:sub(e + 1, nextS - 1) or raw:sub(e + 1)
			local texPath, texW, texH, texIsAtlas, texTitle, texBody = ParseBraceTextureSpec(tip)
			if texPath then
				local tag = BuildTextureTag(texPath, texW, texH, texIsAtlas)
				out[#out + 1] = {
					text = tag,
					icon = true,
					iconSize = texH or texW,
					tooltipIcon = (texTitle or texBody) and tag or nil,
					tooltipTitle = texTitle,
					tooltipBody = texBody,
				}
				if segmentText ~= "" then
					out[#out + 1] = { text = segmentText }
				end
			else
				local iconId, iconSize, iconTitle, iconBody = ParseIconSpec(tip)
				if iconId and iconSize then
					local tag = string.format("|T%s:%d:%d|t", iconId, iconSize, iconSize)
					if segmentText ~= "" then
						out[#out + 1] = {
							text = segmentText,
							tooltipIcon = tag,
							tooltipTitle = iconTitle,
							tooltipBody = iconBody,
						}
					else
						out[#out + 1] = {
							text = tag,
							icon = true,
							iconSize = iconSize,
							tooltipIcon = tag,
							tooltipTitle = iconTitle,
							tooltipBody = iconBody,
						}
					end
				elseif segmentText ~= "" then
					out[#out + 1] = { text = segmentText, tooltip = tip }
				end
			end
			if not nextS then
				break
			end
			i = nextS
		end
		return out
	end

	local function RenderInlineWithTooltips(raw)
		local segments = SplitTooltipSegments(raw or "")
		local displayParts = {}
		local plainParts = {}
		local tooltips = {}
		local plainSoFar = ""

		for _, seg in ipairs(segments) do
			local displayPart = seg.icon and seg.text or RenderInline(seg.text)
			local plainPart
			if seg.icon then
				local spaces = math.max(1, math.floor((seg.iconSize or 16) / 4 + 0.5))
				plainPart = string.rep(" ", spaces)
			else
				plainPart = RenderInlinePlain(seg.text)
			end

			local linkAtlas = nil
			local linkW = nil
			local linkH = nil
			local linkOffsetX = nil
			local linkOffsetY = nil
			if (seg.tooltip or seg.tooltipIcon) and TOOLTIP_LINK_ATLAS and TOOLTIP_LINK_ATLAS ~= "" then
				linkAtlas = TOOLTIP_LINK_ATLAS
				linkW = TOOLTIP_LINK_ATLAS_WIDTH
				linkH = TOOLTIP_LINK_ATLAS_HEIGHT
				linkOffsetX = TOOLTIP_LINK_ATLAS_OFFSET_X
				linkOffsetY = TOOLTIP_LINK_ATLAS_OFFSET_Y
			end

			displayParts[#displayParts + 1] = displayPart
			plainParts[#plainParts + 1] = plainPart
			if seg.tooltipIcon and plainPart ~= "" then
				tooltips[#tooltips + 1] = {
					iconTag = seg.tooltipIcon,
					title = seg.tooltipTitle,
					body = seg.tooltipBody,
					linkAtlas = linkAtlas,
					linkW = linkW,
					linkH = linkH,
					linkOffsetX = linkOffsetX,
					linkOffsetY = linkOffsetY,
					offset = #plainSoFar,
					length = #plainPart,
				}
			elseif seg.tooltip and plainPart ~= "" then
				local title, body = ParseTooltipText(seg.tooltip)
				if title or body then
					tooltips[#tooltips + 1] = {
						title = title,
						body = body,
						linkAtlas = linkAtlas,
						linkW = linkW,
						linkH = linkH,
						linkOffsetX = linkOffsetX,
						linkOffsetY = linkOffsetY,
						offset = #plainSoFar,
						length = #plainPart,
					}
				end
			end
			plainSoFar = plainSoFar .. plainPart
		end

		return table.concat(displayParts), table.concat(plainParts), tooltips
	end

	local function Bio_RenderMarkdown(raw)
		local md = tostring(raw or "")
		md = md:gsub("\r", "")
		local out = {}

		for line in (md .. "\n"):gmatch("(.-)\n") do
			if line:match("^%s*$") then
				out[#out + 1] = ""
			else
				local indent, clean, forceBullet = ParseIndent(line)
				if forceBullet then
					local bulletText = clean:match("^%s*(.+)$")
					if bulletText then
						out[#out + 1] = IndentPrefix(indent) .. "• " .. RenderInline(bulletText)
					end
				else
					local fullTex = clean:match("^%s*{%-%s*(.-)%s*%-%}%s*$")
					if fullTex and fullTex ~= "" then
						local path, _, _, isAtlas = ParseTextureTarget(fullTex)
						if path and path ~= "" then
							local w = 64
							local h = 16
							if isAtlas and C_Texture and C_Texture.GetAtlasInfo then
								local info = C_Texture.GetAtlasInfo(path)
								if info and info.width and info.height and info.width > 0 then
									h = math.max(8, math.floor((w * info.height / info.width) + 0.5))
								end
							end
							out[#out + 1] = IndentPrefix(indent) .. BuildTextureTag(path, w, h, isAtlas)
						end
					else
						local hashes, title = clean:match("^(#+)%s*(.+)$")
						if hashes and title then
							local level = #hashes
							if level < 1 then
								level = 1
							elseif level > 3 then
								level = 3
							end
							local color = (level == 1 and COLOR_H1) or (level == 2 and COLOR_H2) or COLOR_H3
							AppendSpacing(out, H_BEFORE[level] or 0)
							local titleText = RenderInlineWithTooltips(title)
							out[#out + 1] = IndentPrefix(indent) .. color .. titleText .. COLOR_RESET
							AppendSpacing(out, H_SPACING[level] or 0)
						else
							local bullet = clean:match("^%s*[-*]%s+(.+)$")
							if bullet then
								local bulletText = RenderInlineWithTooltips(bullet)
								out[#out + 1] = IndentPrefix(indent) .. "• " .. bulletText
							else
								local lineText = RenderInlineWithTooltips(clean)
								out[#out + 1] = IndentPrefix(indent) .. lineText
							end
						end
					end
				end
			end
		end

		return table.concat(out, "\n")
	end

	local function Bio_RenderMarkdownLines(raw)
		local md = tostring(raw or "")
		md = md:gsub("\r", "")
		local out = {}

		for line in (md .. "\n"):gmatch("(.-)\n") do
			if line:match("^%s*$") then
				out[#out + 1] = { kind = "blank" }
			else
				local indent, clean, forceBullet = ParseIndent(line)
				if forceBullet then
					local bulletText = clean:match("^%s*(.+)$")
					if bulletText then
						local displayText, plainText, tips = RenderInlineWithTooltips(bulletText)
						local prefix = "• "
						for i = 1, #(tips or {}) do
							tips[i].offset = tips[i].offset + #prefix
						end
						out[#out + 1] = {
							kind = "bullet",
							text = prefix .. displayText,
							plain = prefix .. plainText,
							tooltips = tips,
							indent = indent,
						}
					end
				else
					local fullTex = clean:match("^%s*{%-%s*(.-)%s*%-%}%s*$")
					if fullTex and fullTex ~= "" then
						local path, w, h, isAtlas = ParseTextureTarget(fullTex)
						if path and path ~= "" then
							local line = {
								kind = "texture",
								indent = indent,
								width = w,
								height = h,
								fullWidth = true,
							}
							if isAtlas then
								line.atlas = path
								if C_Texture and C_Texture.GetAtlasInfo then
									local info = C_Texture.GetAtlasInfo(path)
									if info and info.width and info.height and info.width > 0 then
										line.ratio = info.height / info.width
									end
								end
							else
								line.texture = path
							end
							out[#out + 1] = line
						end
					else
						local _, imgTarget = clean:match("^%s*!%[([^%]]*)%]%(([^%)]+)%)%s*$")
						if imgTarget then
							local path, w, h, isAtlas = ParseTextureTarget(imgTarget)
							if path and path ~= "" then
								local line = {
									kind = "texture",
									indent = indent,
									width = w,
									height = h,
									fullWidth = not w and not h,
								}
								if isAtlas then
									line.atlas = path
									if C_Texture and C_Texture.GetAtlasInfo then
										local info = C_Texture.GetAtlasInfo(path)
										if info and info.width and info.height and info.width > 0 then
											line.ratio = info.height / info.width
										end
									end
								else
									line.texture = path
								end
								out[#out + 1] = line
							end
						else
							local hashes, title = clean:match("^(#+)%s*(.+)$")
							if hashes and title then
								local level = #hashes
								if level < 1 then
									level = 1
								elseif level > 3 then
									level = 3
								end
								local displayText, plainText, tips = RenderInlineWithTooltips(title)
								out[#out + 1] = {
									kind = "h" .. level,
									text = displayText,
									plain = plainText,
									tooltips = tips,
									indent = indent,
									before = H_BEFORE[level] or 0,
									after = H_SPACING[level] or 0,
								}
							else
								local bullet = clean:match("^%s*[-*]%s+(.+)$")
								if bullet then
									local displayText, plainText, tips = RenderInlineWithTooltips(bullet)
									local prefix = "• "
									for i = 1, #(tips or {}) do
										tips[i].offset = tips[i].offset + #prefix
									end
									out[#out + 1] = {
										kind = "bullet",
										text = prefix .. displayText,
										plain = prefix .. plainText,
										tooltips = tips,
										indent = indent,
									}
								else
									local displayText, plainText, tips = RenderInlineWithTooltips(clean)
									out[#out + 1] = {
										kind = "text",
										text = displayText,
										plain = plainText,
										tooltips = tips,
										indent = indent,
									}
								end
							end
						end
					end
				end
			end
		end

		return out
	end

	local function Bio_StripMarkdown(raw)
		local text = tostring(raw or "")
		text = text:gsub("\r", "")
		text = text:gsub("^%s*#+%s*", "")
		text = text:gsub("\n%s*#+%s*", "\n")
		text = text:gsub("!%[([^%]]*)%]%(([^%)]+)%)", "%1")
		text = text:gsub("%[(.-)%]%((.-)%)", "%1")
		text = text:gsub("%*%*(.-)%*%*", "%1")
		text = text:gsub("%*(.-)%*", "%1")
		return text
	end

	fn.Bio_RenderMarkdown = Bio_RenderMarkdown
	fn.Bio_RenderMarkdownLines = Bio_RenderMarkdownLines
	fn.Bio_StripMarkdown = Bio_StripMarkdown
end

return M
