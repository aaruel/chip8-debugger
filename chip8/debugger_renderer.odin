package main

Debugger :: struct {
    window: ^Window,
}

start_debugger :: proc{start_debugger_sdl}
tick_debugger :: proc{tick_debugger_sdl}

destroy_debugger_impl :: proc{destroy_debugger_sdl}

destroy_debugger :: proc(debugger: ^Debugger) {
    destroy_debugger_impl(auto_cast debugger)
    free(debugger)
}

new_debugger :: proc($T: typeid) -> ^T {
    ret: ^T = new(T)
    return ret
}
