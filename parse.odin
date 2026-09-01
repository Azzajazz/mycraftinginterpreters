#+feature dynamic-literals

package lox

import "core:fmt"
import "core:os"
import "core:reflect"

Ast_Type :: enum {
    Number,
    String,
   
    Negate,

    Plus,
    Times,
    Minus,
}

Ast :: struct {
    type: Ast_Type,

    file_name: string,
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

Ast_Unary_Operator :: struct {
    using expr: Ast_Expression,

    operand: ^Ast_Expression,
}

Ast_Negate :: distinct Ast_Unary_Operator

Ast_Binary_Operator :: struct {
    using expr: Ast_Expression,

    left: ^Ast_Expression,
    right: ^Ast_Expression,
}

Ast_Plus :: distinct Ast_Binary_Operator
Ast_Minus :: distinct Ast_Binary_Operator
Ast_Times :: distinct Ast_Binary_Operator

ast_types := map[typeid]Ast_Type {
    Ast_Number = .Number,
    Ast_String = .String,
    Ast_Negate = .Negate,
    Ast_Plus = .Plus,
    Ast_Minus = .Minus,
    Ast_Times = .Times,
}

new_ast_node :: proc($T: typeid, file_name: string, line_start, char_start: int, line_end, char_end: int) -> ^T {
    ast := new(T)
    ast.type = ast_types[T]

    ast.file_name = file_name
    ast.line_start = line_start
    ast.char_start = char_start
    ast.line_end = line_end
    ast.char_end = char_end

    return ast
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

    case .Negate:
        operator := cast(^Ast_Unary_Operator)ast

        dump_indent(indent)
        fmt.print("  operand = ")
        dump_ast(operator.operand, indent + 1)

    case .Plus: fallthrough
    case .Minus: fallthrough
    case .Times:
        operator := cast(^Ast_Binary_Operator)ast

        dump_indent(indent)
        fmt.print("  left = ")
        dump_ast(operator.left, indent + 1)

        dump_indent(indent)
        fmt.print("  right = ")
        dump_ast(operator.right, indent + 1)
    }
    dump_indent(indent)
    fmt.println(")")
}

Parser :: struct {
    using lexer: ^Lexer,
}

parse_all :: proc(parser: ^Parser) -> []^Ast {
    program: [dynamic]^Ast

    statement := parse_statement(parser)
    for statement != nil {
        append(&program, statement)
        statement = parse_statement(parser)
    }

    return program[:]
}

parse_statement :: proc(parser: ^Parser) -> ^Ast_Statement {
    return parse_expression(parser)
}

MIN_BINDING_POWER :: 10 // @Volatile: Must be updated with binding_powers.
binding_powers := map[Token_Type]int{
    .Plus = 10,
    .Minus = 10,
    .Star = 20,
}

parse_expression :: proc(parser: ^Parser, max_binding_power := MIN_BINDING_POWER) -> ^Ast_Expression {
    line_start := parser.line
    char_start := parser.char

    left := parse_expression_leaf(parser)
    maybe_operator := peek_token(parser.lexer)
    binding_power, has_binding := binding_powers[maybe_operator.type]
    for has_binding {
        lex_token(parser.lexer) // Actually consume the operator.
        
        right: ^Ast_Expression
        if binding_power > max_binding_power {
            right = parse_expression(parser, binding_power)
        } else {
            right = parse_expression_leaf(parser)
        }
        
        // @Incomplete: Parse all operator types.
        ast_operator: ^Ast_Binary_Operator
        if maybe_operator.type == .Plus {
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Plus, parser.file_name, line_start, char_start, parser.line, parser.char)
        } else if maybe_operator.type == .Minus {
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Minus, parser.file_name, line_start, char_start, parser.line, parser.char)
        } else if maybe_operator.type == .Star {
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Times, parser.file_name, line_start, char_start, parser.line, parser.char)
        }
        assert(ast_operator != nil)
        ast_operator.left = left
        ast_operator.right = right

        left = ast_operator

        maybe_operator = peek_token(parser.lexer)
        binding_power, has_binding = binding_powers[maybe_operator.type]
    }

    return left
}

parse_expression_leaf :: proc(parser: ^Parser) -> ^Ast_Expression {
    line_start := parser.line
    char_start := parser.char

    is_negate := false

    token := lex_token(parser.lexer)
    if token.type == .Minus {
        is_negate = true
        token = lex_token(parser.lexer)
    }

    if token.type == .Eof {
        return nil
    }

    expr: ^Ast_Expression
    if token.type == .LeftParen {
        expr = parse_expression(parser)
        token = lex_token(parser.lexer)
        if token.type != .RightParen {
            report_error(expr, "Expected a ')', but got %v.", token.code)
        }
    } else {
        #partial switch token.type {
        case .Number:
            ast := new_ast_node(Ast_Number, parser.file_name, line_start, char_start, parser.line, parser.char)

            ast.value = token.value.number
            expr = cast(^Ast_Expression)ast

        case .String:
            ast := new_ast_node(Ast_String, parser.file_name, line_start, char_start, parser.line, parser.char)
            ast.value = token.value.str
            expr = cast(^Ast_Expression)ast

        case:
            report_internal_error("Unsupported token type %v when parsing an expression leaf.", token.type)
        }
    }

    if is_negate {
        negate := new_ast_node(Ast_Negate, parser.file_name, line_start, char_start, parser.line, parser.char)
        negate.operand = expr
        return negate
    } else {
        return expr
    }
}
