package chip8

Window :: struct {
    width: i32,
    height: i32,
}

create_window :: proc{create_window_sdl}
should_close_window :: proc{should_close_window_sdl}
tick_window :: proc{tick_window_sdl}
destroy_window :: proc{destroy_window_sdl}

new_window :: proc($T: typeid, width: i32, height: i32) -> ^T {
    obj: ^T = new(T)
    obj.width = width
    obj.height = height
    create_window(obj)
    return obj
}