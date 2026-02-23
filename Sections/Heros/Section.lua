local ADDON, ns = ...

ns.Sections = ns.Sections or {}

local M = ns.HerosSection

function ns.Sections.Heros(parent)
	local ctx = M.CreateContext(parent)

	M.BuildBaseUI(ctx)
	M.BuildNewsCore(ctx)
	M.BuildNewsFeatured(ctx)
	M.BuildBio(ctx)
	M.BuildNewsList(ctx)
	M.BuildRoster(ctx)
	M.BindEvents(ctx)

	return ctx.ui.frame
end
