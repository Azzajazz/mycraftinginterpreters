package lox

import "core:flags"
import "core:os"
import "core:fmt"
import "core:mem"
import vmem "core:mem/virtual"

report_internal_error :: proc(format: string, args: ..any) {
    fmt.eprint("Internal error: ")
    fmt.eprintfln(format, ..args)
    panic("Internal error!")
}

Options :: struct {
    source_file: string `args:"pos=0,required" usage:"The source file to interpret."`,
    expr_mode: bool `usage:"Evaluate a single expression only. Used for testing."`,
    lex_only: bool `usage:"Only lex the input."`,
    parse_only: bool `usage:"Only parse the input."`,
    ast_dump: bool `usage:"Dump the parsed AST."`,
}
options: Options

main :: proc() {
    flags.parse_or_exit(&options, os.args)

    source_file_data, source_file_data_err := os.read_entire_file(options.source_file, context.allocator)
    defer delete(source_file_data)
    if source_file_data_err != nil {
        fmt.eprintfln("ERROR: Could not open source file %v.", options.source_file)
        os.exit(1)
    }

    lexer := Lexer{file_name = options.source_file, code = cast(string)source_file_data, code_index = 0}
    if options.lex_only {
        token: Token
        for token.type != .Eof {
            token = lex_token(&lexer)
            dump_token(token)
        }
    } else {
        arena: vmem.Arena
        err := vmem.arena_init_growing(&arena)
        assert(err == nil)
        context.allocator = vmem.arena_allocator(&arena)

        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        defer mem.tracking_allocator_destroy(&track)
        context.allocator = mem.tracking_allocator(&track)

        parser := Parser{lexer = &lexer}
        if options.expr_mode {
            expr := parse_expression(&parser)

            if options.ast_dump {
                dump_ast(expr)
            }

            if !options.parse_only {
                interp := Interp{}
                value := evaluate_expression(&interp, expr)
                fmt.println(value.value.number)
            }
        } else {
            global_scope := parse_all(&parser)
            if options.ast_dump {
                dump_ast(global_scope)
            }

            if !options.parse_only {
                interp := Interp{}
                evaluate(&interp, global_scope)
            }
        }

        free_all(context.allocator)

        for _, leak in track.allocation_map {
            fmt.printfln("%v leaked %m", leak.location, leak.size)
        }
    }
}
