package chip8

import "vendor:sdl2"
import "vendor:microui"
import "core:mem"
import "core:fmt"

Microui_SDL :: struct {
    res_atlas: ^sdl2.Texture,
    res_ctx: ^microui.Context,
}

create_mu_sdl :: proc(window: ^Window_SDL) -> ^Microui_SDL {
    obj: ^Microui_SDL = new(Microui_SDL)
    
    // start microui
    obj.res_ctx = new(microui.Context)
    microui.init(obj.res_ctx)

    obj.res_ctx.text_width = mu_get_text_width
    obj.res_ctx.text_height = mu_get_text_height

    obj.res_atlas = sdl2.CreateTexture(
        window.renderer, 
        u32(sdl2.PixelFormatEnum.RGBA32), 
        sdl2.TextureAccess.TARGET, 
        microui.DEFAULT_ATLAS_WIDTH, 
        microui.DEFAULT_ATLAS_HEIGHT)

    assert(obj.res_atlas != nil)

    sdl2.SetTextureBlendMode(obj.res_atlas, sdl2.BlendMode.BLEND)

    // convert the atlas alpha to 32bit rgba
    rgba8_conv, alloc_err := mem.make([]u32, microui.DEFAULT_ATLAS_WIDTH * microui.DEFAULT_ATLAS_HEIGHT)
    defer delete(rgba8_conv)

    for x in 0..<microui.DEFAULT_ATLAS_WIDTH {
        for y in 0..<microui.DEFAULT_ATLAS_HEIGHT {
            index := y*microui.DEFAULT_ATLAS_WIDTH + x
            rgba8_conv[index] = 0x00FFFFFF | (u32(microui.default_atlas_alpha[index]) << 24)
        }
    }

    // pitch is the length of the row in bytes
    tex_err := sdl2.UpdateTexture(obj.res_atlas, nil, &rgba8_conv[0], 4 * microui.DEFAULT_ATLAS_WIDTH)
    if tex_err != 0 {
        fmt.println("UpdateTexture() {s}", sdl2.GetError())
    }

    // recieve a callback from sdl to handle mouse events
    window.event_cbs[mu_event_callback_sdl] = obj
    
    return obj
}

destroy_mu_sdl :: proc(obj: ^Microui_SDL, window: ^Window_SDL) {
    delete_key(&window.event_cbs, mu_event_callback_sdl)
    delete(window.event_cbs)
    free(obj.res_ctx)

    free(obj)
}

mu_mouse_sdl :: proc(button: u8) -> microui.Mouse {
    switch button {
        case 1: return .LEFT
        case 2: return .MIDDLE
        case 3: return .RIGHT
    }

    return .LEFT
}

mu_event_callback_sdl :: proc(user: rawptr, event: ^sdl2.Event) {
    obj := transmute(^Microui_SDL)user

    #partial switch event.type {
        case .MOUSEMOTION:
            microui.input_mouse_move(obj.res_ctx, event.motion.x, event.motion.y)
        case .MOUSEBUTTONDOWN:
            microui.input_mouse_down(obj.res_ctx, event.button.x, event.button.y, mu_mouse_sdl(event.button.button))
        case .MOUSEBUTTONUP:
            microui.input_mouse_up(obj.res_ctx, event.button.x, event.button.y, mu_mouse_sdl(event.button.button))
    }
}

mu_clear_screen :: proc(window: ^Window_SDL, color: microui.Color) {
    sdl2.SetRenderDrawColor(window.renderer, color.r, color.g, color.b, color.a)
    sdl2.RenderClear(window.renderer)
}

mu_present :: proc(window: ^Window_SDL) {
    sdl2.RenderPresent(window.renderer)
}

mu_set_clip_rect :: proc(window: ^Window_SDL, clip: ^microui.Command_Clip) {
    sdl_rect := transmute(sdl2.Rect)clip.rect
    sdl2.RenderSetClipRect(window.renderer, &sdl_rect)
}

mu_draw_icon :: proc(obj: ^Microui_SDL, window: ^Window_SDL, ic: ^microui.Command_Icon) {
    icon := microui.default_atlas[int(ic.id)]
    x := ic.rect.x + (ic.rect.w - icon.w) / 2
    y := ic.rect.y + (ic.rect.h - icon.h) / 2
    atlas_quad(obj, window, {x, y, icon.w, icon.h}, icon, ic.color)
}

mu_draw_rect :: proc(obj: ^Microui_SDL, window: ^Window_SDL, rect: ^microui.Command_Rect) {
    atlas_quad(obj, window, rect.rect, microui.default_atlas[microui.DEFAULT_ATLAS_WHITE], rect.color)
}

mu_draw_text :: proc(obj: ^Microui_SDL, window: ^Window_SDL, using text: ^microui.Command_Text) {
    dst := microui.Rect{ text.pos.x, text.pos.y, 0, 0 };
    for ch in text.str {
        if ch&0xc0 == 0x80 do continue;
        chr := min(int(ch), 127);
        src := microui.default_atlas[microui.DEFAULT_ATLAS_FONT + chr]
        dst.w = src.w;
        dst.h = src.h;
        atlas_quad(obj, window, dst, src, color);
        dst.x += dst.w;
    }
}

mu_get_text_width :: proc(font: microui.Font, text: string) -> (res: i32) {
    for ch in text {
        if ch&0xc0 == 0x80 do continue
        chr := min(int(ch), 127)
        res += microui.default_atlas[microui.DEFAULT_ATLAS_FONT + chr].w
    }
    return
}

mu_get_text_height :: proc(font: microui.Font) -> i32 {
    return 18
}

mu_draw :: proc(obj: ^Microui_SDL, window: ^Window_SDL) {
    // renderer
    mu_clear_screen(window, microui.Color{128, 128, 128, 255})

    cmd: ^microui.Command
    for microui.next_command(obj.res_ctx, &cmd) {
        variant := cmd.variant
        switch in variant {
            case ^microui.Command_Text: mu_draw_text(obj, window, variant.(^microui.Command_Text));
            case ^microui.Command_Rect: mu_draw_rect(obj, window, variant.(^microui.Command_Rect));
            case ^microui.Command_Icon: mu_draw_icon(obj, window, variant.(^microui.Command_Icon));
            case ^microui.Command_Clip: mu_set_clip_rect(window, variant.(^microui.Command_Clip));
            case ^microui.Command_Jump: unreachable() /* handled internally by next_command() */
        }
    }
}

@(private="file")
atlas_quad :: proc(obj: ^Microui_SDL, window: ^Window_SDL, dst, src: microui.Rect, using color: microui.Color) {
    src := transmute(sdl2.Rect) src
    dst := transmute(sdl2.Rect) dst
    sdl2.SetTextureAlphaMod(obj.res_atlas, a)
    sdl2.SetTextureColorMod(obj.res_atlas, r, g, b)
    sdl2.RenderCopy(window.renderer, obj.res_atlas, &src, &dst)
}
