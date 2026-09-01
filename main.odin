package lox

import "core:flags"
import "core:os"
import "core:fmt"

report_internal_error :: proc(format: string, args: ..any) {
    fmt.eprint("Internal error: ")
    fmt.eprintfln(format, ..args)
    panic("Internal error!")
}

Options :: struct {
    source_file: string `args:"pos=0,required" usage:"The source file to interpret."`,
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
        os.exit(0)
    }

    parser := Parser{lexer = &lexer}
    program := parse_all(&parser)
    if options.ast_dump {
        for ast in program {
            dump_ast(ast)
        }
    }

    if options.parse_only {
        os.exit(0)
    }

    interp := Interp{}
    for ast in program {
        ast_expr := cast(^Ast_Expression)ast
        value := evaluate_expression(&interp, ast_expr)
        fmt.println(value.value.number)
    }
}
