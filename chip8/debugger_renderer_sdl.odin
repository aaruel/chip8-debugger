package main

import "vendor:sdl2"
import "vendor:microui"
import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:path/filepath"
import "core:os"
import "core:strings"

Debugger_SDL :: struct {
    using base: Debugger,
    impl_window: ^Window_SDL,

    // microui
    mu: ^Microui_SDL,

    // display
    viewport: ^sdl2.Texture,

    vp_scale: i32,
}

ViewportDrawCommand :: struct {
    src_rect: sdl2.Rect,
    dst_rect: sdl2.Rect,
}

start_debugger_sdl :: proc(debugger: ^Debugger_SDL, impl_window: ^Window_SDL) {
    // dont start twice
    assert(debugger.window == nil)
    debugger.impl_window = impl_window
    debugger.mu = create_mu_sdl(impl_window)

    debugger.vp_scale = 8
    
    debugger.viewport = sdl2.CreateTexture(
        impl_window.renderer, 
        u32(sdl2.PixelFormatEnum.RGB332), // 1 byte per pixel
        sdl2.TextureAccess.TARGET, 
        i32(CPU_PROG_DISPLAY_SIZE.x), 
        i32(CPU_PROG_DISPLAY_SIZE.y))
}

tick_debugger_sdl :: proc(debugger: ^Debugger_SDL, cpu: ^CpuState) {
    display_size : [2]i32 = {i32(CPU_PROG_DISPLAY_SIZE.x), i32(CPU_PROG_DISPLAY_SIZE.y)}

    ctx := debugger.mu.res_ctx

    // keep the table updated
    update_debug_instruction_table(cpu, {10, 10})

    // update the texture with the buffer drawn directly from the cpu
    vp_rect := sdl2.Rect{0, 0, display_size.x, display_size.y}
    // since this is 8 bits per pixel, the pitch == display.x
    sdl2.UpdateTexture(debugger.viewport, &vp_rect, &cpu.display[0], display_size.x)

    // draw code
    microui.begin(ctx)

    db_txt: string = cpu.running ? "Debugger |>" : "Debugger ||";

    if microui.begin_window(ctx, db_txt, microui.Rect{10, 10, 240, 552}) {
        range := cpu.debug_instruction_table.addr_range
        for addr := range[0]; addr <= range[1]; addr += 2 {
            microui.layout_row(ctx, {10, 40, 170}, 20)
            microui.label(ctx, cpu.pc == addr ? ">" : " ")
            microui.label(ctx, fmt.tprintf("0x%X", addr))
            microui.label(ctx, cpu.debug_instruction_table.table[addr])
        }

        microui.layout_row(ctx, {113, 113}, 20)

        step_in: microui.Result_Set = microui.button(ctx, "Step In =>")
        if .SUBMIT in step_in {
            process_next_instruction(cpu)
        }
        
        step_out: microui.Result_Set = microui.button(ctx, "Step Out <= (INOP)")
        if .SUBMIT in step_out {
            unimplemented("once we get a visual stack trace we can do this")
        }
        
        microui.layout_row(ctx, {113, 113}, 20)
        play: microui.Result_Set = microui.button(ctx, "Play |>")
        if .SUBMIT in play {
            cpu.running = true
        }

        pause: microui.Result_Set = microui.button(ctx, "Pause ||")
        if .SUBMIT in pause {
            cpu.running = false
        }

        microui.end_window(ctx)
    }

    vp_cmd: ViewportDrawCommand
    sz := display_size * debugger.vp_scale
    if microui.begin_window(ctx, "Viewport", microui.Rect{260, 10, sz.x, sz.y}) {
        c := microui.get_current_container(ctx)

        render_area := c.rect
        vp_cmd.src_rect = transmute(sdl2.Rect) vp_rect
        vp_cmd.dst_rect = transmute(sdl2.Rect) render_area

        microui.end_window(ctx)
    }

    if microui.begin_window(ctx, "Registers", microui.Rect{270 + sz.x, 10, 240, 552}) {
        for r := 0; r < len(cpu.gp_registers); r += 1 {
            microui.layout_row_items(ctx, 2, 20)
            microui.label(ctx, fmt.tprintf("v%X", r))
            microui.label(ctx, fmt.tprintf("%d (0x%X)", cpu.gp_registers[r], cpu.gp_registers[r]))
        }

        microui.layout_row_items(ctx, 2, 20)
        microui.label(ctx, "I")
        microui.label(ctx, fmt.tprintf("%d (0x%X)", cpu.i_register, cpu.i_register))

        microui.layout_row_items(ctx, 2, 20)
        microui.label(ctx, "sound")
        microui.label(ctx, fmt.tprintf("%d (0x%X)", cpu.sound_timer_register, cpu.sound_timer_register))

        microui.layout_row_items(ctx, 2, 20)
        microui.label(ctx, "delay")
        microui.label(ctx, fmt.tprintf("%d (0x%X)", cpu.delay_timer_register, cpu.delay_timer_register))

        microui.layout_row_items(ctx, 2, 20)
        microui.label(ctx, "PC")
        microui.label(ctx, fmt.tprintf("%d (0x%X)", cpu.pc, cpu.pc))

        microui.end_window(ctx)
    }

    if microui.begin_window(ctx, "Input", microui.Rect{260, 20 + sz.y, 223, 286}) {
        microui.layout_row(ctx, {50, 50, 50, 50}, 50)
        if .SUBMIT in microui.button(ctx, "1") { incl(&cpu.input, 0x1) }
        if .SUBMIT in microui.button(ctx, "2") { incl(&cpu.input, 0x2) }
        if .SUBMIT in microui.button(ctx, "3") { incl(&cpu.input, 0x3) }
        if .SUBMIT in microui.button(ctx, "C") { incl(&cpu.input, 0xC) }

        microui.layout_row(ctx, {50, 50, 50, 50}, 50)
        if .SUBMIT in microui.button(ctx, "4") { incl(&cpu.input, 0x4) }
        if .SUBMIT in microui.button(ctx, "5") { incl(&cpu.input, 0x5) }
        if .SUBMIT in microui.button(ctx, "6") { incl(&cpu.input, 0x6) }
        if .SUBMIT in microui.button(ctx, "D") { incl(&cpu.input, 0xD) }

        microui.layout_row(ctx, {50, 50, 50, 50}, 50)
        if .SUBMIT in microui.button(ctx, "7") { incl(&cpu.input, 0x7) }
        if .SUBMIT in microui.button(ctx, "8") { incl(&cpu.input, 0x8) }
        if .SUBMIT in microui.button(ctx, "9") { incl(&cpu.input, 0x9) }
        if .SUBMIT in microui.button(ctx, "E") { incl(&cpu.input, 0xE) }

        microui.layout_row(ctx, {50, 50, 50, 50}, 50)
        if .SUBMIT in microui.button(ctx, "A") { incl(&cpu.input, 0xA) }
        if .SUBMIT in microui.button(ctx, "0") { incl(&cpu.input, 0x0) }
        if .SUBMIT in microui.button(ctx, "B") { incl(&cpu.input, 0xB) }
        if .SUBMIT in microui.button(ctx, "F") { incl(&cpu.input, 0xF) }

        // if we're paused and we're doing an input, process the next instruction
        if !cpu.running && cpu.input != {} {
            process_next_instruction(cpu)
        }

        microui.end_window(ctx)
    }

    if microui.begin_window(ctx, "Loader", microui.Rect{493, 20 + sz.y, 279, 286}) {
        microui.layout_row(ctx, {269}, 20)

        if !cpu.loaded {
            cwd := os.get_current_directory(context.temp_allocator)
            emu_dir := strings.concatenate({cwd, "/emu"}, context.temp_allocator)

            UserPtrs :: struct {
                ctx: ^microui.Context,
                cpu: ^CpuState,
                found: bool,
            }
            ptrs: UserPtrs = {ctx, cpu, false}

            walker := proc(info: os.File_Info, in_err: os.Errno, user_data: rawptr) -> (err: os.Errno, skip_dir: bool) {
                ext := filepath.ext(info.name)
                if ext != ".ch8" {
                    return
                }

                w_ptrs := transmute(^UserPtrs)user_data
                w_ctx := w_ptrs.ctx
                w_cpu := w_ptrs.cpu

                if .SUBMIT in microui.button(w_ctx, fmt.tprintf("Load %s", info.name)) {
                    fd, err := os.open(info.fullpath)
                    if err != os.ERROR_NONE {
                        fmt.printf("can't open the file because %s", err)
                        return
                    }

                    bytes, ok := os.read_entire_file_from_handle(fd)
                    if !ok {
                        return
                    }

                    load_program(w_cpu, bytes)
                }

                w_ptrs.found = true

                return
            }

            filepath.walk(emu_dir, walker, &ptrs)

            if !ptrs.found {
                microui.label(ctx, fmt.tprintf("Nothing found in %s", emu_dir))
            }
        }
        else {
            microui.label(ctx, "Reset to load another program...")
            if .SUBMIT in microui.button(ctx, "Reset CPU") { reset_cpu(cpu) }
        }

        microui.end_window(ctx)
    }

    if microui.begin_window(ctx, "Config", microui.Rect{520 + sz.x, 10, 240, 552}) {
        fields := reflect.struct_fields_zipped(CpuConfig)

        for field in fields {
            field_ptr := uintptr(&cpu.config) + field.offset

            switch field.type.id {
                case bool: {
                    microui.layout_row(ctx, {230})
                    microui.checkbox(ctx, field.name, transmute(^bool)field_ptr)
                }
                case f32: {
                    microui.layout_row(ctx, {110, 115})
                    microui.label(ctx, field.name)
                    microui.slider(ctx, transmute(^f32)field_ptr, 300.0, 1000.0, 100.0)
                }
            }
        }

        microui.end_window(ctx)
    }

    microui.end(ctx)

    mu_draw(debugger.mu, debugger.impl_window)

    // draw the viewport on top of everything
    sdl2.RenderCopy(
        debugger.impl_window.renderer, 
        debugger.viewport, 
        &vp_cmd.src_rect, 
        &vp_cmd.dst_rect)

    mu_present(debugger.impl_window)
}

destroy_debugger_sdl :: proc(debugger: ^Debugger_SDL) {
    destroy_mu_sdl(debugger.mu, debugger.impl_window)
}
