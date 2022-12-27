package main

import "vendor:sdl2"
import "core:fmt"
import "core:io"
import "core:os"
import "core:runtime"

EventCB :: proc(rawptr, ^sdl2.Event)

Window_SDL :: struct {
    using base: Window,
    window: ^sdl2.Window,
    renderer: ^sdl2.Renderer,
    should_close: bool,
    event_cbs: map[EventCB]rawptr,
}

create_window_sdl :: proc(ret: ^Window_SDL) {
    if sdl2.Init(sdl2.INIT_VIDEO) < 0 {
        fmt.println("couldnt init sdl2")
        return
    }
    
    ret.window = sdl2.CreateWindow(
        "c h i p 8", 
        sdl2.WINDOWPOS_UNDEFINED, 
        sdl2.WINDOWPOS_UNDEFINED, 
        ret.width, 
        ret.height,
        sdl2.WINDOW_SHOWN)

    ret.renderer = sdl2.CreateRenderer(
        ret.window, 
        -1, 
        sdl2.RendererFlags{sdl2.RendererFlag.ACCELERATED})
}

should_close_window_sdl :: proc(ret: ^Window_SDL) -> bool {
    return ret.should_close
}

tick_window_sdl :: proc(ret: ^Window_SDL) {
    event: sdl2.Event
    for sdl2.PollEvent(&event) {
        // route to callbacks
        for k,v in ret.event_cbs {
            k(v, &event)
        }
        
        #partial switch event.type {
            case .QUIT: {
                ret.should_close = true
            }
        }
    }

    sdl2.Delay(7)
}

destroy_window_sdl :: proc(ret: ^Window_SDL) {
    sdl2.DestroyWindow(ret.window)
    sdl2.Quit()
    free(ret)
}
