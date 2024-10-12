package main

import "core:slice"

import im "deps:odin-imgui"
import im_vk "deps:odin-imgui/imgui_impl_vulkan"

configure_im :: proc() {
	io := im.GetIO()

	font_config: im.FontConfig = {}

	font_config.FontDataOwnedByAtlas = true
	font_config.OversampleH = 6
	font_config.OversampleV = 6
	font_config.GlyphMaxAdvanceX = max(f32)
	font_config.RasterizerMultiply = 1.4
	font_config.RasterizerDensity = 1.0
	font_config.EllipsisChar = cast(im.Wchar)(max(u16))

	font_config.PixelSnapH = false
	font_config.GlyphOffset = {0.0, -1.0}

	im.FontAtlas_AddFontFromFileTTF(io.Fonts, "C:\\Windows\\Fonts\\segoeui.ttf", 18.0, &font_config)

	font_config.MergeMode = true

	ICON_MIN_FA: u16 : 0xe005
	ICON_MAX_FA: u16 : 0xf8ff

	@(static) FA_RANGES: [3]u16 = {ICON_MIN_FA, ICON_MAX_FA, 0}

	font_config.RasterizerMultiply = 1.0
	font_config.GlyphOffset = {0.0, -1.0}

	im.FontAtlas_AddFontFromFileTTF(io.Fonts, "assets/fa-regular-400.ttf", 14.0, &font_config, slice.as_ptr(FA_RANGES[:]))

	font_config.MergeMode = false

	style := im.GetStyle()

	tone_text_1: im.Vec4 : {0.69, 0.69, 0.69, 1.0}
	tone_text_2: im.Vec4 : {0.69, 0.69, 0.69, 0.8}

	tone_1: im.Vec4 : {0.16, 0.16, 0.18, 1.0}
	tone_1_b := tone_1 * 1.2
	tone_1_e := tone_1 * 1.7
	tone_1_e_a := tone_1_e
	tone_2: im.Vec4 : {0.12, 0.12, 0.13, 1.0}
	tone_2_b: im.Vec4 = tone_2
	tone_3: im.Vec4 : {0.11, 0.11, 0.12, 1.0}

	style.Colors[im.Col.Text] = tone_text_1
	style.Colors[im.Col.TextDisabled] = tone_text_2
	style.Colors[im.Col.WindowBg] = tone_1
	style.Colors[im.Col.ChildBg] = tone_2
	style.Colors[im.Col.PopupBg] = tone_2_b
	style.Colors[im.Col.Border] = tone_2
	style.Colors[im.Col.BorderShadow] = {0.0, 0.0, 0.0, 0.0}
	style.Colors[im.Col.FrameBg] = tone_3
	style.Colors[im.Col.FrameBgHovered] = tone_3
	style.Colors[im.Col.FrameBgActive] = tone_3
	style.Colors[im.Col.TitleBg] = tone_2
	style.Colors[im.Col.TitleBgActive] = tone_2
	style.Colors[im.Col.TitleBgCollapsed] = tone_2
	style.Colors[im.Col.MenuBarBg] = tone_2
	style.Colors[im.Col.ScrollbarBg] = tone_3
	style.Colors[im.Col.ScrollbarGrab] = tone_1_e
	style.Colors[im.Col.ScrollbarGrabHovered] = tone_1_e
	style.Colors[im.Col.ScrollbarGrabActive] = tone_1_e_a
	style.Colors[im.Col.CheckMark] = tone_1_e
	style.Colors[im.Col.SliderGrab] = tone_1_e
	style.Colors[im.Col.SliderGrabActive] = tone_1_e_a
	style.Colors[im.Col.Button] = tone_2
	style.Colors[im.Col.ButtonHovered] = tone_2
	style.Colors[im.Col.ButtonActive] = tone_3
	style.Colors[im.Col.Header] = tone_2
	style.Colors[im.Col.HeaderHovered] = tone_2
	style.Colors[im.Col.HeaderActive] = tone_2
	style.Colors[im.Col.Separator] = tone_2
	style.Colors[im.Col.SeparatorHovered] = tone_2
	style.Colors[im.Col.SeparatorActive] = tone_2
	style.Colors[im.Col.ResizeGrip] = {0.0, 0.0, 0.0, 0.0}
	style.Colors[im.Col.ResizeGripHovered] = {0.0, 0.0, 0.0, 0.0}
	style.Colors[im.Col.ResizeGripActive] = {0.0, 0.0, 0.0, 0.0}
	style.Colors[im.Col.Tab] = tone_2
	style.Colors[im.Col.TabHovered] = tone_1
	style.Colors[im.Col.TabActive] = tone_1
	style.Colors[im.Col.TabUnfocused] = tone_1
	style.Colors[im.Col.TabUnfocusedActive] = tone_1
	style.Colors[im.Col.PlotLines] = tone_1_e
	style.Colors[im.Col.PlotLinesHovered] = tone_2
	style.Colors[im.Col.PlotHistogram] = tone_1_e
	style.Colors[im.Col.PlotHistogramHovered] = tone_2
	style.Colors[im.Col.TableHeaderBg] = tone_2
	style.Colors[im.Col.TableBorderStrong] = tone_2
	style.Colors[im.Col.TableBorderLight] = tone_2
	style.Colors[im.Col.TableRowBg] = tone_2
	style.Colors[im.Col.TableRowBgAlt] = tone_1
	style.Colors[im.Col.TextSelectedBg] = tone_1_e
	style.Colors[im.Col.DragDropTarget] = tone_2
	style.Colors[im.Col.NavHighlight] = tone_2
	style.Colors[im.Col.NavWindowingHighlight] = tone_2
	style.Colors[im.Col.NavWindowingDimBg] = tone_2_b
	style.Colors[im.Col.ModalWindowDimBg] = tone_2_b * 0.5

	style.Colors[im.Col.DockingPreview] = {1.0, 1.0, 1.0, 0.5}
	style.Colors[im.Col.DockingEmptyBg] = {0.0, 0.0, 0.0, 0.0}

	style.WindowPadding = {10.00, 10.00}
	style.FramePadding = {5.00, 5.00}
	style.CellPadding = {2.50, 2.50}
	style.ItemSpacing = {5.00, 5.00}
	style.ItemInnerSpacing = {5.00, 5.00}
	style.TouchExtraPadding = {5.00, 5.00}
	style.IndentSpacing = 10
	style.ScrollbarSize = 15
	style.GrabMinSize = 10
	style.WindowBorderSize = 0
	style.ChildBorderSize = 0
	style.PopupBorderSize = 0
	style.FrameBorderSize = 0
	style.TabBorderSize = 0
	style.WindowRounding = 10
	style.ChildRounding = 5
	style.FrameRounding = 5
	style.PopupRounding = 5
	style.GrabRounding = 5
	style.ScrollbarRounding = 10
	style.LogSliderDeadzone = 5
	style.TabRounding = 5
	style.DockingSeparatorSize = 5
}
