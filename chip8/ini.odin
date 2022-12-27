package main
import "core:strconv"
import "core:reflect"
import "core:os"
import "core:fmt"

CFG_INI_PATH :: "config.ini"

@(private="file")
parse_string :: proc($T: typeid, v: string, ptr: uintptr, conv: proc(string, ^int) -> (T, bool)) {
    val, ok := conv(v, nil)
    if ok {
        (transmute(^T)ptr)^ = val
    }
}

@(private="file")
parse_int :: proc(s: string, n: ^int = nil) -> (int, bool) {
    return strconv.parse_int(s, 0, n)
}

@(private="file")
parse_ini_line :: proc($T: typeid, obj: ^T, line: string) {
    for c in 0..<len(line) {
        if line[c] == '=' {
            k := line[0:c]
            v := line[c+1:len(line)]

            field := reflect.struct_field_by_name(CpuConfig, k)
            if len(field.name) == 0 {
                return
            }

            ptr := uintptr(obj) + field.offset
            switch field.type.id {
                case bool: parse_string(bool, v, ptr, strconv.parse_bool)
                case f32: parse_string(f32, v, ptr, strconv.parse_f32)
                case int: parse_string(int, v, ptr, parse_int)
            }

            return
        }
    }
}

serialize_ini :: proc($T: typeid, obj: ^T, loading: bool = false) {
    props := reflect.struct_field_names(CpuConfig)

    cfg_name := CFG_INI_PATH

    if loading && !os.exists(cfg_name) {
        // create it then
        serialize_ini(T, obj)
        return
    }

    if !loading {
        os.remove(cfg_name)
    }
    
    fd, err := os.open(cfg_name, os.O_RDWR | os.O_CREATE)

    if err != os.ERROR_NONE {
        fmt.printf("can't open the config file because %s", err)
        return
    }

    if loading {
        data, success := os.read_entire_file_from_handle(fd)
        defer delete(data)

        if success {
            start_idx := 0
            end_idx := 0

            for idx in 0..<len(data) {
                if data[idx] == '\n' || data[idx] == 0 {
                    end_idx = idx
                    slc := data[start_idx:end_idx]
                    parse_ini_line(T, obj, string(slc))
                    start_idx = end_idx + 1
                }
            }
        }
    }
    else {
        for prop in props {
            v := reflect.struct_field_value_by_name(obj^, prop)
            str := fmt.tprintf("%s={}\n", prop, v)
            os.write_string(fd, str)
        }
    }

    os.close(fd)
}
