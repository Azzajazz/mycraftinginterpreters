package lox

import "core:fmt"
import "core:os"
import "core:reflect"

Ast_Type :: enum {
    Number,
    String,
    Plus,
}

Ast :: struct {
    type: Ast_Type,

    line_start: int,
    char_start: int,

    line_end: int,
    char_end: int,
}

Ast_Statement :: struct {
    using ast: Ast,
}

Ast_Expression :: struct {
    using stmt: Ast_Statement,
}

Ast_Number :: struct {
    using expr: Ast_Expression,

    value: f32,
}

Ast_String :: struct {
    using expr: Ast_Expression,

    value: string,
}

Ast_Plus :: struct {
    using expr: Ast_Expression,

    left: ^Ast_Expression,
    right: ^Ast_Expression,
}

dump_indent :: proc(indent: int) {
    for _ in 0..<indent {
        fmt.print("  ")
    }
}

dump_ast :: proc(ast: ^Ast, indent := 0) {
    indent := indent

    enum_field, _ := reflect.enum_name_from_value(ast.type)
    fmt.printfln("%v(", enum_field)
    switch ast.type {
    case .Number:
        number := cast(^Ast_Number)ast

        dump_indent(indent)
        fmt.printfln("  value = %v", number.value)

    case .String:
        str := cast(^Ast_String)ast

        dump_indent(indent)
        fmt.printfln("  value = %v", str.value)

    case .Plus:
        plus := cast(^Ast_Plus)ast

        dump_indent(indent)
        fmt.print("  left = ")
        dump_ast(plus.left, indent + 1)

        dump_indent(indent)
        fmt.print("  right = ")
        dump_ast(plus.right, indent + 1)
    }
    dump_indent(indent)
    fmt.println(")")
}

report_parse_error :: proc(parser: ^Parser, ast: Ast, format: string, args: ..any) {
    fmt.eprintf("%v(%v:%v) Error: ", parser.file_name, ast.line_start + 1, ast.char_start + 1)
    fmt.eprintfln(format, ..args)
    os.exit(1)
}

Parser :: struct {
    using lexer: ^Lexer,
}

parse_statement :: proc(parser: ^Parser) -> ^Ast_Statement {
    return parse_expression(parser)
}

parse_expression :: proc(parser: ^Parser) -> ^Ast_Expression {
    line_start := parser.line
    char_start := parser.char

    // @Hack: Some hardcoded stuff here.
    left := parse_expression_leaf(parser)
    assert(left != nil)
    operator := lex_token(parser.lexer)
    assert(operator.type == .Plus)
    right := parse_expression_leaf(parser)
    assert(right != nil)
    
    expr := new(Ast_Plus)
    expr.type = .Plus

    expr.line_start = line_start
    expr.char_start = char_start
    expr.line_end = parser.line
    expr.char_end = parser.char

    expr.left = left
    expr.right = right

    return expr
}

parse_expression_leaf :: proc(parser: ^Parser) -> ^Ast_Expression {
    line_start := parser.line
    char_start := parser.char

    token := lex_token(parser.lexer)
    #partial switch token.type {
    case .Number:
        expr := new(Ast_Number)
        expr.type = .Number

        expr.line_start = line_start
        expr.char_start = char_start
        expr.line_end = parser.line
        expr.char_end = parser.char

        expr.value = token.value.number

        return expr

    case .String:
        expr := new(Ast_String)
        expr.type = .String

        expr.line_start = line_start
        expr.char_start = char_start
        expr.line_end = parser.line
        expr.char_end = parser.char

        expr.value = token.value.str

        return expr

    case:
        report_internal_error("Unsupported token type %v when parsing an expression", token.type)
    }

    unreachable()
}
