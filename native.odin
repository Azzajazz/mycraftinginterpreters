package lox

import "core:time"

@(private)
interp_start: time.Tick

clock :: proc() -> f32 {
    now := time.tick_now()
    diff_millis := time.tick_diff(interp_start, now) / 1000000
    diff_seconds := cast(f32)diff_millis / 1000
    return diff_seconds
}
