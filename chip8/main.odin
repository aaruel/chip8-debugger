package main

import "core:time"
import "core:fmt"
import "core:mem"

main :: proc() {
    // set up a custom allocator so we can catch leaks
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    context.allocator = mem.tracking_allocator(&track)

    cpu: CpuState
    init_cpu(&cpu)

    window := new_window(Window_SDL, 1280, 570)
    debugger := new_debugger(Debugger_SDL)
    start_debugger(debugger, window)
    
    curr_time: time.Time
    last_time: time.Time
    for should_close_window(window) == false {
        time_slice := time.duration_seconds(time.diff(last_time, curr_time))
        
        {
            tick_cpu(&cpu, time_slice)
            tick_window(window)
            tick_debugger(debugger, &cpu)
        }
        
        last_time = curr_time
        curr_time = time.now()
    }
    
    destroy_debugger(debugger)
    destroy_window(window)
    destroy_cpu_state(&cpu)

    if len(track.allocation_map) > 0 {
        fmt.println()
		for _, v in track.allocation_map {
			fmt.printf("%v Leaked %v bytes.\n", v.location, v.size)
		}
    }
}
