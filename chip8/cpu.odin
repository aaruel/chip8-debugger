package main

import "core:fmt"
import "core:mem"
import "core:math"
import "core:math/bits"
import "core:math/rand"
import "core:bytes"

// special mem addresses
CPU_PROG_ADDRESS_LOWER_BOUND : u16be : 0x0200 // where programs get loaded
CPU_PROG_ADDRESS_UPPER_BOUND : u16be : 0x0E8F // the end of the available program memory (using the 4096 byte variant)
CPU_PROG_MEM_SIZE : u16be : 0x1000
CPU_PROG_INSTRUCTION_SIZE : u16be : 0x2
CPU_PROG_TIMER_INTERVAL : f64 : 1.0/60.0
CPU_PROG_DISPLAY_SIZE : [2]u8 : {64, 32}
CPU_PROG_DISPLAY_INTERRUPT_TIME : f64 : 1.0/60.0

InstructionFormat :: enum {
    x00E0,
    x00EE,
    x0NNN,
    x1NNN,
    x2NNN,
    x3XKK,
    x4XKK,
    x5XY0,
    x6XKK,
    x7XKK,
    x8XY0,
    x8XY1,
    x8XY2,
    x8XY3,
    x8XY4,
    x8XY5,
    x8XY6,
    x8XY7,
    x8XYE,
    x9XY0,
    xANNN,
    xBNNN,
    xCXKK,
    xDXYN,
    xEX9E,
    xEXA1,
    xFX07,
    xFX0A,
    xFX15,
    xFX18,
    xFX1E,
    xFX29,
    xFX33,
    xFX55,
    xFX65,
    UNKNOWN,
}

DebugInstructionTable :: struct {
    table: map[u16be]string,
    // this is storing the absolute lower and upper range of the memory, [0] < [1]
    addr_range: [2]u16be,
}

CpuConfig :: struct {
    clock_speed: f32, // limitation of microui, use f32 instead of f64
    vf_reset: bool,
    memory: bool,
    display_wait: bool,
    clipping: bool,
    shifting: bool,
    jumping: bool,
}

CpuState :: struct {
    // registers
    pc: u16be,
    sp: u16be,

    // RAM allocation
    ram: [CPU_PROG_MEM_SIZE]u8,
    stack: [16]u16be, // the documentation doesn't say this points into main memory
    gp_registers: [16]u8,
    i_register: u16be,
    delay_timer_register: u8,
    sound_timer_register: u8,

    // internal state
    rand_gen: rand.Rand,
    clock_speed: f64,
    timer_trig: f64,
    display_interrupt_signal: bool,
    display_interrupt_time: f64,

    // display buffer for the viewport texture
    display: [u16(CPU_PROG_DISPLAY_SIZE.x) * u16(CPU_PROG_DISPLAY_SIZE.y)]u8,

    // input bits
    input: bit_set[0..=15],

    // debug state
    debug_instruction_table: DebugInstructionTable,
    last_instruction_addr: u16be,
    running: bool,
    config: CpuConfig,
    loaded: bool,
}

rom_sprite_address :: proc(num: u8) -> u16be {
    assert(num >= 0 && num < 16)
    return 5 * u16be(num)
}

get_key_press :: proc(state: ^CpuState) -> (u8, bool) {
    for k in 0..=15 {
        if k in state.input {
            return u8(k), true
        }
    }

    return 0, false
}

tick_timer_registers :: proc(state: ^CpuState, dt: f64) {
    if state.timer_trig >= CPU_PROG_TIMER_INTERVAL {
        if state.delay_timer_register > 0 {
            state.delay_timer_register -= 1
        }

        if state.sound_timer_register > 0 {
            state.sound_timer_register -= 1
        }

        state.timer_trig = 0.0
    }
    else {
        state.timer_trig += dt
    }
}

tick_display_interrupt :: proc(state: ^CpuState, dt: f64) {
    if state.display_interrupt_time >= CPU_PROG_DISPLAY_INTERRUPT_TIME {
        // only signal on the rising edge
        state.display_interrupt_signal = true
        state.display_interrupt_time = 0.0
    }
    else {
        state.display_interrupt_signal = false
        state.display_interrupt_time += dt
    }
}

init_cpu :: proc(state: ^CpuState) {
    // set up the stack
    //state.sp = 15
    // just consider zero the top
    state.rand_gen = rand.create(0x0123_4567_89AB_CDEF)

    // clock speed is adjustable, but 500HZ works in general
    state.clock_speed = 500

    // ROM sprites
    // 0
    state.ram[0] = 0xF0
    state.ram[1] = 0x90
    state.ram[2] = 0x90
    state.ram[3] = 0x90
    state.ram[4] = 0xF0
    // 1
    state.ram[5] = 0x20
    state.ram[6] = 0x60
    state.ram[7] = 0x20
    state.ram[8] = 0x20
    state.ram[9] = 0x70
    // 2
    state.ram[10] = 0xF0
    state.ram[11] = 0x10
    state.ram[12] = 0xF0
    state.ram[13] = 0x80
    state.ram[14] = 0xF0
    // 3
    state.ram[15] = 0xF0
    state.ram[16] = 0x10
    state.ram[17] = 0xF0
    state.ram[18] = 0x10
    state.ram[19] = 0xF0
    // 4
    state.ram[20] = 0x90
    state.ram[21] = 0x90
    state.ram[22] = 0xF0
    state.ram[23] = 0x10
    state.ram[24] = 0x10
    // 5
    state.ram[25] = 0xF0
    state.ram[26] = 0x80
    state.ram[27] = 0xF0
    state.ram[28] = 0x10
    state.ram[29] = 0xF0
    // 6
    state.ram[30] = 0xF0
    state.ram[31] = 0x80
    state.ram[32] = 0xF0
    state.ram[33] = 0x90
    state.ram[34] = 0xF0
    // 7
    state.ram[35] = 0xF0
    state.ram[36] = 0x10
    state.ram[37] = 0x20
    state.ram[38] = 0x40
    state.ram[39] = 0x40
    // 8
    state.ram[40] = 0xF0
    state.ram[41] = 0x90
    state.ram[42] = 0xF0
    state.ram[43] = 0x90
    state.ram[44] = 0xF0
    // 9
    state.ram[45] = 0xF0
    state.ram[46] = 0x90
    state.ram[47] = 0xF0
    state.ram[48] = 0x10
    state.ram[49] = 0xF0
    // A
    state.ram[50] = 0xF0
    state.ram[51] = 0x90
    state.ram[52] = 0xF0
    state.ram[53] = 0x90
    state.ram[54] = 0x90
    // B
    state.ram[55] = 0xE0
    state.ram[56] = 0x90
    state.ram[57] = 0xE0
    state.ram[58] = 0x90
    state.ram[59] = 0xE0
    // C
    state.ram[60] = 0xF0
    state.ram[61] = 0x80
    state.ram[62] = 0x80
    state.ram[63] = 0x80
    state.ram[64] = 0xF0
    // D
    state.ram[65] = 0xE0
    state.ram[66] = 0x90
    state.ram[67] = 0x90
    state.ram[68] = 0x90
    state.ram[69] = 0xE0
    // E
    state.ram[70] = 0xF0
    state.ram[71] = 0x80
    state.ram[72] = 0xF0
    state.ram[73] = 0x80
    state.ram[74] = 0xF0
    // F
    state.ram[75] = 0xF0
    state.ram[76] = 0x80
    state.ram[77] = 0xF0
    state.ram[78] = 0x80
    state.ram[79] = 0x80

    { // default chip8 config
        state.config.clock_speed = 500.0
        state.config.vf_reset = true
        state.config.memory = true
        state.config.display_wait = true
        state.config.clipping = true
        state.config.shifting = false
        state.config.jumping = false

        serialize_ini(CpuConfig, &state.config, true)
    }
}

deref_address :: proc($T: typeid, state: ^CpuState, addr: u16be) -> T {
    ptr := transmute(^T)&state.ram[addr]
    return ptr^
}

current_instruction :: proc(state: ^CpuState, offset: int = 0) -> u16be {
    return deref_address(u16be, state, state.pc)
}

get_instruction :: proc(state: ^CpuState, addr: u16be) -> u16be {
    return deref_address(u16be, state, addr)
}

get_instruction_format :: proc(instruction: u16be) -> InstructionFormat {
    switch (instruction & 0xF000) {
        case 0x0000: switch (instruction) {
            case 0x00EE: return .x00EE
            case 0x00E0: return .x00E0
            case: return .x0NNN
        }
        case 0x1000: return .x1NNN
        case 0x2000: return .x2NNN
        case 0x3000: return .x3XKK
        case 0x4000: return .x4XKK
        case 0x5000: return .x5XY0
        case 0x6000: return .x6XKK
        case 0x7000: return .x7XKK
        case 0x8000: switch (instruction & 0x000F) {
            case 0x0: return .x8XY0
            case 0x1: return .x8XY1
            case 0x2: return .x8XY2
            case 0x3: return .x8XY3
            case 0x4: return .x8XY4
            case 0x5: return .x8XY5
            case 0x6: return .x8XY6
            case 0x7: return .x8XY7
            case 0xE: return .x8XYE
        }
        case 0x9000: return .x9XY0
        case 0xA000: return .xANNN
        case 0xB000: return .xBNNN
        case 0xC000: return .xCXKK
        case 0xD000: return .xDXYN
        case 0xE000: switch (instruction & 0x00FF) {
            case 0x009E: return .xEX9E
            case 0x00A1: return .xEXA1
        }
        case 0xF000: switch (instruction & 0x00FF) {
            case 0x0007: return .xFX07
            case 0x000A: return .xFX0A
            case 0x0015: return .xFX15
            case 0x0018: return .xFX18
            case 0x001E: return .xFX1E
            case 0x0029: return .xFX29
            case 0x0033: return .xFX33
            case 0x0055: return .xFX55
            case 0x0065: return .xFX65
        }
    }

    return .UNKNOWN
}

register_x :: proc (instruction: u16be) -> u8 {
    // big endian types need to be explicitly cast for bit shifting, this is currently a bug https://github.com/odin-lang/Odin/issues/2264
    return u8((instruction & 0x0F00) >> u16be(8))
}

register_y :: proc (instruction: u16be) -> u8 {
    return u8((instruction & 0x00F0) >> u16be(4))
}

literal_nnn :: proc (instruction: u16be) -> u16be {
    return instruction & 0x0FFF
}

literal_kk :: proc (instruction: u16be) -> u8 {
    return u8(instruction & 0x00FF)
}

literal_n :: proc(instruction: u16be) -> u8 {
    return u8(instruction & 0x000F)
}

// the offset here is the relative offset from the PC (in bytes, remember, instructions are 2 bytes)
update_debug_instruction_table :: proc(state: ^CpuState, offset: [2]u16) {
    assert(offset % 2 == 0) // ensure we aren't getting half an instruction

    prev_low_addr := state.debug_instruction_table.addr_range[0]
    prev_high_addr := state.debug_instruction_table.addr_range[1]

    offset_be: [2]u16be = {u16be(offset[0]), u16be(offset[1])}

    low_addr := max(CPU_PROG_ADDRESS_LOWER_BOUND, state.pc - offset_be[0])
    high_addr := min(state.last_instruction_addr, state.pc + offset_be[1])

    // clean up any previous keys
    for addr := prev_low_addr; addr <= prev_high_addr; addr += 2 {
        out_of_range := addr < low_addr || addr > high_addr

        if out_of_range && addr in state.debug_instruction_table.table {
            // since we're using aprintf here 
            delete(state.debug_instruction_table.table[addr])
            delete_key(&state.debug_instruction_table.table, addr)
        }
    }

    // calculate any new keys
    for addr := low_addr; addr <= high_addr; addr += 2 {
        if addr not_in state.debug_instruction_table.table {
            instruction := get_instruction(state, addr)
            format := get_instruction_format(instruction)

            result: string

            x := register_x(instruction)
            y := register_y(instruction)
            nnn := literal_nnn(instruction)
            kk := literal_kk(instruction)
            n := literal_n(instruction)
            b0 := (instruction & 0xFF00) >> u16be(8)
            b1 := (instruction & 0x00FF)

            switch format {
                case .x00E0:
                    result = fmt.aprintf("CLS")
                case .x00EE:
                    result = fmt.aprintf("RET")
                case .x0NNN:
                    result = fmt.aprintf("SYS 0x%X", nnn)
                case .x1NNN:
                    result = fmt.aprintf("JP 0x%X", nnn)
                case .x2NNN:
                    result = fmt.aprintf("CALL 0x%X", nnn)
                case .x3XKK:
                    result = fmt.aprintf("SE v%X, 0x%X", x, kk)
                case .x4XKK:
                    result = fmt.aprintf("SNE v%X, 0x%X", x, kk)
                case .x5XY0:
                    result = fmt.aprintf("SE v%X, v%X", x, y)
                case .x6XKK:
                    result = fmt.aprintf("LD v%X, 0x%X", x, kk)
                case .x7XKK:
                    result = fmt.aprintf("ADD v%X, 0x%X", x, kk)
                case .x8XY0:
                    result = fmt.aprintf("LD v%X, v%X", x, y)
                case .x8XY1:
                    result = fmt.aprintf("OR v%X, v%X", x, y)
                case .x8XY2:
                    result = fmt.aprintf("AND v%X, v%X", x, y)
                case .x8XY3:
                    result = fmt.aprintf("XOR v%X, v%X", x, y)
                case .x8XY4:
                    result = fmt.aprintf("ADD v%X, v%X", x, y)
                case .x8XY5:
                    result = fmt.aprintf("SUB v%X, v%X", x, y)
                case .x8XY6:
                    result = fmt.aprintf("SHR v%X, v%X", x, y)
                case .x8XY7:
                    result = fmt.aprintf("SUBN v%X, v%X", x, y)
                case .x8XYE:
                    result = fmt.aprintf("SHL v%X, v%X", x, y)
                case .x9XY0:
                    result = fmt.aprintf("SNE v%X, v%X", x, y)
                case .xANNN:
                    result = fmt.aprintf("LD I, 0x%X", nnn)
                case .xBNNN:
                    result = fmt.aprintf("JP V0, 0x%X", nnn)
                case .xCXKK:
                    result = fmt.aprintf("RND v%X, 0x%X", x, kk)
                case .xDXYN:
                    result = fmt.aprintf("DRW v%X, v%X, 0x%X", x, y, n)
                case .xEX9E:
                    result = fmt.aprintf("SKP v%X", x)
                case .xEXA1:
                    result = fmt.aprintf("SKNP v%X", x)
                case .xFX07:
                    result = fmt.aprintf("LD v%X, DelayTimer", x)
                case .xFX0A:
                    result = fmt.aprintf("LD v%X, Key", x)
                case .xFX15:
                    result = fmt.aprintf("LD DelayTimer, v%X", x)
                case .xFX18:
                    result = fmt.aprintf("LD SoundTimer, v%X", x)
                case .xFX1E:
                    result = fmt.aprintf("ADD I, v%X", x)
                case .xFX29:
                    result = fmt.aprintf("LD F, v%X", x)
                case .xFX33:
                    result = fmt.aprintf("LD B, v%X", x)
                case .xFX55:
                    result = fmt.aprintf("LD [I], v%X", x)
                case .xFX65:
                    result = fmt.aprintf("LD v%X, [I]", x)
                case .UNKNOWN:
                    result = fmt.aprintf("0x%X 0x%X", b0, b1)
            }

            assert(len(result) != 0)

            state.debug_instruction_table.table[addr] = result
        }
    }

    state.debug_instruction_table.addr_range[0] = low_addr
    state.debug_instruction_table.addr_range[1] = high_addr
}

process_next_instruction :: proc(state: ^CpuState) {
    instruction := current_instruction(state)
    format := get_instruction_format(instruction)
    advance_pc := true

    assert(format != .UNKNOWN)

    switch format {
        case .x00E0: {
            mem.set(&state.display[0], 0x00, len(state.display))
        }
        case .x00EE: {
            // return from subroutine
            assert(state.sp > 0)
            state.pc = state.stack[state.sp]
            state.sp -= 1
        }
        case .x0NNN: {
            unimplemented("0x0NNN : Modern interpreters ignore this, this is a hardware specific instruction")
        }
        case .x1NNN: {
            // this is a clean jump, it does not modify the stack
            state.pc = literal_nnn(instruction)
            assert(state.pc < CPU_PROG_MEM_SIZE)
            advance_pc = false
        }
        case .x2NNN: {
            // call a subroutine
            assert(state.sp <= 15)
            state.sp += 1
            state.stack[state.sp] = state.pc
            state.pc = literal_nnn(instruction)
            assert(state.pc < CPU_PROG_MEM_SIZE)
            advance_pc = false
        }
        case .x3XKK: {
            // skip instruction if VX == KK
            if state.gp_registers[register_x(instruction)] == literal_kk(instruction) {
                state.pc += CPU_PROG_INSTRUCTION_SIZE
            }
        }
        case .x4XKK: {
            // skip instruction if VX != KK
            if state.gp_registers[register_x(instruction)] != literal_kk(instruction) {
                state.pc += CPU_PROG_INSTRUCTION_SIZE
            }
        }
        case .x5XY0: {
            // skip instruction if VX == VY
            if state.gp_registers[register_x(instruction)] == state.gp_registers[register_y(instruction)] {
                state.pc += CPU_PROG_INSTRUCTION_SIZE
            }
        }
        case .x6XKK: {
            // set VX = KK
            state.gp_registers[register_x(instruction)] = literal_kk(instruction)
        }
        case .x7XKK: {
            // VX = VX + KK
            state.gp_registers[register_x(instruction)] += literal_kk(instruction)
        }
        case .x8XY0: {
            // VX = VY
            state.gp_registers[register_x(instruction)] = state.gp_registers[register_y(instruction)]
        }
        case .x8XY1: {
            // VX = VX | VY
            state.gp_registers[register_x(instruction)] |= state.gp_registers[register_y(instruction)]

            if state.config.vf_reset {
                state.gp_registers[0xF] = 0
            }
        }
        case .x8XY2: {
            // VX = VX & VY
            state.gp_registers[register_x(instruction)] &= state.gp_registers[register_y(instruction)]

            if state.config.vf_reset {
                state.gp_registers[0xF] = 0
            }
        }
        case .x8XY3: {
            // VX = VX xor VY
            state.gp_registers[register_x(instruction)] ~= state.gp_registers[register_y(instruction)]

            if state.config.vf_reset {
                state.gp_registers[0xF] = 0
            }
        }
        case .x8XY4: {
            // VX = VX + VY, VF = 1 if overflow else 0
            x_ptr := &state.gp_registers[register_x(instruction)]
            x := u16be(x_ptr^)
            y := u16be(state.gp_registers[register_y(instruction)])
            result: u16be = x + y
            state.gp_registers[0xF] = result > 0xFF ? 1 : 0
            x_ptr^ = u8(result & 0xFF)
        }
        case .x8XY5: {
            // VX = VX - VY, VF = 1 if x > y else 0
            x_ptr := &state.gp_registers[register_x(instruction)]
            x := x_ptr^
            y := state.gp_registers[register_y(instruction)]
            result := x - y
            state.gp_registers[0xF] = x >= y ? 1 : 0
            x_ptr^ = result
        }
        case .x8XY6: {
            // VX = VX >> 1, VF = 1 if a 1 is shifted out
            x_ptr := &state.gp_registers[register_x(instruction)]

            // default behavior is to set VX to VY before shifting
            if !state.config.shifting {
                x_ptr^ = state.gp_registers[register_y(instruction)]
            }
            
            x := x_ptr^
            x_ptr^ >>= 1
            state.gp_registers[0xF] = (x & 1) == 1 ? 1 : 0
        }
        case .x8XY7: {
            // VX = VY - VX, VF = 1 if y >= x else 0
            x_ptr := &state.gp_registers[register_x(instruction)]
            x := x_ptr^
            y := state.gp_registers[register_y(instruction)]
            result := y - x
            state.gp_registers[0xF] = y >= x ? 1 : 0
            x_ptr^ = result
        }
        case .x8XYE: {
            // VX = VX << 1, VF = 1 if a 1 is shifted out
            x_ptr := &state.gp_registers[register_x(instruction)]

            // default behavior is to set VX to VY before shifting
            if !state.config.shifting {
                x_ptr^ = state.gp_registers[register_y(instruction)]
            }

            x := x_ptr^
            x_ptr^ <<= 1
            state.gp_registers[0xF] = (x & 0x80) == 0x80 ? 1 : 0
        }
        case .x9XY0: {
            // skip instruction if VX != VY
            if state.gp_registers[register_x(instruction)] != state.gp_registers[register_y(instruction)] {
                state.pc += CPU_PROG_INSTRUCTION_SIZE
            }
        }
        case .xANNN: {
            // I = nnn
            state.i_register = literal_nnn(instruction)
        }
        case .xBNNN: {
            // jump to nnn + V0
            offset := u16be(state.gp_registers[state.config.jumping ? register_x(instruction) : 0])

            state.pc = literal_nnn(instruction) + offset
            advance_pc = false
            assert(state.pc < CPU_PROG_MEM_SIZE)
        }
        case .xCXKK: {
            // generate random value [0, 255], mask with KK
            r := u32be(rand.uint32(&state.rand_gen))
            mask := u32be(literal_kk(instruction))
            state.gp_registers[register_x(instruction)] = u8(r & mask)
        }
        case .xDXYN: {
            // draw command

            // if waiting for the interrupt, dont do anything, but only when running
            if state.config.display_wait && !state.display_interrupt_signal && state.running {
                advance_pc = false
                break
            }

            // read N bytes from memory starting from i_register
            n := literal_n(instruction)
            sprite: [16]u8

            for it: u8 = 0; it < n; it += 1 {
                sprite[it] = state.ram[state.i_register + u16be(it)]
            }

            // bytes are displayed as sprites at (VX, VY)
            x := state.gp_registers[register_x(instruction)]
            y := state.gp_registers[register_y(instruction)]

            // sprites are xor'd onto the existing screen
            // if this causes pixels to be erased, VF is set to 1 otherwise 0.
            // coordinates wrap around to the other side
            // the screen is 64x32
            state.gp_registers[0xF] = 0

            // this might wrap around too
            //assert(x < 64 && y < 32)
            x = x % CPU_PROG_DISPLAY_SIZE.x
            y = y % CPU_PROG_DISPLAY_SIZE.y
            
            for x_off: u16 = 0; x_off < 8; x_off += 1 {
                for y_off: u16 = 0; y_off < u16(n); y_off += 1 {
                    pix: u8 = (sprite[y_off] >> (7 - x_off)) & 0x1

                    // clipping applies to the bottom of the screen
                    if state.config.clipping {
                        clip_x: bool = (u16(x) + x_off) >= u16(CPU_PROG_DISPLAY_SIZE.x)
                        clip_y: bool = (u16(y) + y_off) >= u16(CPU_PROG_DISPLAY_SIZE.y)
                        
                        if clip_x || clip_y {
                            continue
                        }
                    }

                    // wrap around
                    it_x := (u16(x) + x_off) % u16(CPU_PROG_DISPLAY_SIZE.x)
                    it_y := (u16(y) + y_off) % u16(CPU_PROG_DISPLAY_SIZE.y)

                    pix_addr := &state.display[u16(CPU_PROG_DISPLAY_SIZE.x) * it_y + it_x]

                    // since the display is using an R8 format, only consider the LSB
                    curr_pix := pix_addr^ & 0x1

                    // since we xor the existing value, we have to check if 1 xor 1 will switch a pixel off
                    if pix == 1 && curr_pix == 1 {
                        state.gp_registers[0xF] = 1
                    }

                    pix_addr^ = (pix ~ curr_pix) & 0x1 == 1 ? 0xFF : 0x00
                }
            }
        }
        case .xEX9E: {
            // skip the next instruction if the input is pressed
            x := state.gp_registers[register_x(instruction)]
            if int(x) in state.input {
                state.pc += CPU_PROG_INSTRUCTION_SIZE
                state.input = {}
            }
        }
        case .xEXA1: {
            // skip the next instruction if the input is not pressed
            x := state.gp_registers[register_x(instruction)]
            if int(x) not_in state.input {
                state.pc += CPU_PROG_INSTRUCTION_SIZE
            }
            else {
                state.input = {}
            }
        }
        case .xFX07: {
            // store the delay timer in VX
            state.gp_registers[register_x(instruction)] = state.delay_timer_register
        }
        case .xFX0A: {
            // wait for a key press, store the value in VX
            key, key_state := get_key_press(state)
            state.gp_registers[register_x(instruction)] = key

            // blocking until key is pressed
            if key_state == false {
                advance_pc = false
            }
            else {
                state.input = {}
            }
        }
        case .xFX15: {
            // set the delay timer
            state.delay_timer_register = state.gp_registers[register_x(instruction)]
        }
        case .xFX18: {
            // set the sound timer
            state.sound_timer_register = state.gp_registers[register_x(instruction)]
        }
        case .xFX1E: {
            // increment the i register by VX
            state.i_register += u16be(state.gp_registers[register_x(instruction)])
        }
        case .xFX29: {
            // set I register to the corresponding rom sprite
            state.i_register = rom_sprite_address(state.gp_registers[register_x(instruction)])
        }
        case .xFX33: {
            // store the binary coded decimal representation in I, I+1, I+2
            x := state.gp_registers[register_x(instruction)]
            h := x / 100
            t := (x - h * 100) / 10
            o := x % 10

            state.ram[state.i_register + 0] = h // hundreds
            state.ram[state.i_register + 1] = t // tens
            state.ram[state.i_register + 2] = o // ones
        }
        case .xFX55: {
            // store V0-Vx in memory starting at i_register
            for n: u8 = 0; n <= register_x(instruction); n += 1 {
                // memory config option increments the i register rather than using a literal
                i_addr := state.config.memory ? state.i_register : state.i_register + u16be(n)

                state.ram[i_addr] = state.gp_registers[n]

                if state.config.memory {
                    state.i_register += 1
                }
            }
        }
        case .xFX65: {
            // read V0-Vx in memory starting at i_register
            for n: u8 = 0; n <= register_x(instruction); n += 1 {
                // memory config option increments the i register rather than using a literal
                i_addr := state.config.memory ? state.i_register : state.i_register + u16be(n)

                state.gp_registers[n] = state.ram[i_addr]

                if state.config.memory {
                    state.i_register += 1
                }
            }
        }
        case .UNKNOWN: {
            unimplemented("bad instruction")
        }
    }

    if advance_pc {
        state.pc += CPU_PROG_INSTRUCTION_SIZE
    }
}

load_program :: proc(state: ^CpuState, src: []u8) {
    // something is wrong if a program is trying to load when one is already loaded
    assert(state.pc == 0)

    // make sure the program can fit
    num_bytes := u16be(len(src))
    assert(num_bytes <= CPU_PROG_ADDRESS_UPPER_BOUND - CPU_PROG_ADDRESS_LOWER_BOUND)

    low := CPU_PROG_ADDRESS_LOWER_BOUND
    high := low + num_bytes

    copy_slice(state.ram[low:high], src)

    // each instruction is 16 bits, 
    state.pc = low
    state.last_instruction_addr = high

    state.loaded = true
}

reset_cpu :: proc(state: ^CpuState) {
    destroy_cpu_state(state)
    state^ = {}
    init_cpu(state)
}

tick_cpu :: proc(state: ^CpuState, time_slice: f64) {
    if !state.running {
        return
    }

    // floor
    num_instructions := i64(time_slice * state.clock_speed)
    instruction_time := time_slice / f64(num_instructions)

    for instruction in 0..<num_instructions {
        tick_timer_registers(state, instruction_time)
        tick_display_interrupt(state, instruction_time)
        process_next_instruction(state)
    }
}

destroy_cpu_state :: proc(state: ^CpuState) {
    for _, v in state.debug_instruction_table.table {
        delete(v)
    }

    delete(state.debug_instruction_table.table)
}
