#+feature dynamic-literals

package lox

import "base:runtime"

import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strconv"

// @TODO: Adding new AST nodes is error-prone and requires:
//   - adding an entry to Ast_Type
//   - defining the new AST structure
//   - adding the mapping to ast_types.
// Surely we can automate some of this?

Ast_Type :: enum {
    // Statements that are not expressions.
    Print,
    VarDefinition,

    // Expressions.
    Number,
    String,
    Bool,
    Nil,
   
    Negate,

    Plus,
    Times,
    Minus,
    Divide,

    Equal,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,

    Var,
    Scope,
}

Ast :: struct {
    type: Ast_Type,

    file_name: string,
    // @Cleanup: Remove these.
    line_start: int,
    char_start: int,

    line_end: int,
    char_end: int,
    // @Cleanup

    start_code_index: int,
    end_code_index: int,
}

Ast_Scope :: struct {
    using ast: Ast,

    parent: ^Ast_Scope,
    // @Memory @Cleanup :DynamicArrayInArena
    children: [dynamic]^Ast,
}

Ast_Statement :: struct {
    using ast: Ast,
}

Ast_Print :: struct {
    using stmt: Ast_Statement,

    expr: ^Ast_Expression,
}

Ast_Var_Definition :: struct {
    using stmt: Ast_Statement,

    name: string,
    value: ^Ast_Expression,
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

Ast_Bool :: struct {
    using expr: Ast_Expression,

    value: bool,
}

Ast_Nil :: struct {
    using expr: Ast_Expression,
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
Ast_Divide :: distinct Ast_Binary_Operator
Ast_Equal :: distinct Ast_Binary_Operator
Ast_Less :: distinct Ast_Binary_Operator
Ast_LessEqual :: distinct Ast_Binary_Operator
Ast_Greater :: distinct Ast_Binary_Operator
Ast_GreaterEqual :: distinct Ast_Binary_Operator

Ast_Var :: struct {
    using expr: Ast_Expression,

    name: string,
}

ast_types := map[typeid]Ast_Type {
    Ast_Scope = .Scope,
    Ast_Print = .Print,
    Ast_Var_Definition = .VarDefinition,
    Ast_Number = .Number,
    Ast_String = .String,
    Ast_Bool = .Bool,
    Ast_Nil = .Nil,
    Ast_Negate = .Negate,
    Ast_Plus = .Plus,
    Ast_Minus = .Minus,
    Ast_Times = .Times,
    Ast_Divide = .Divide,
    Ast_Equal = .Equal,
    Ast_Less = .Less,
    Ast_LessEqual = .LessEqual,
    Ast_Greater = .Greater,
    Ast_GreaterEqual = .GreaterEqual,
    Ast_Var = .Var,
}

// @Volatile: Must be kept in sync with Ast_Type.
is_expression :: proc(ast: ^Ast) -> bool {
    expression_min := cast(int)Ast_Type.Number
    return cast(int)ast.type >= expression_min
}

new_ast_node :: proc($T: typeid, start_code_index, end_code_index: int, line_start, char_start: int, parser: ^Parser) -> ^T {
    ast := new(T, parser.ast_allocator)
    ast.type = ast_types[T]

    ast.file_name = parser.file_name
    ast.line_start = line_start
    ast.char_start = char_start
    ast.line_end = parser.line
    ast.char_end = parser.char

    ast.start_code_index = start_code_index
    ast.end_code_index = end_code_index

    
    // @Memory @Cleanup :DynamicArrayInArena
    // I don't really want to append using a linear allocator,
    // but it's difficult to clean up this memory otherwise. At some point we may
    // come up with a better memory allocation strategy, but for now this is the best
    // we can do.
    when T == Ast_Scope {
        ast.children.allocator = parser.ast_allocator
    }

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
    case .Scope:
        scope := cast(^Ast_Scope)ast
        dump_indent(indent)
        fmt.println("  children = [")

        for child in scope.children {
            dump_indent(indent + 2)
            dump_ast(child, indent + 2)
        }

        dump_indent(indent)
        fmt.println("  ]")

    case .Print:
        print := cast(^Ast_Print)ast

        dump_indent(indent)
        fmt.print("  expr = ")

        dump_ast(print.expr, indent + 1)

    case .VarDefinition:
        var_def := cast(^Ast_Var_Definition)ast

        dump_indent(indent)
        fmt.printfln("  name = %v", var_def.name)

        dump_indent(indent)
        fmt.print("  value = ")

        dump_ast(var_def.value, indent + 1)

    case .Number:
        number := cast(^Ast_Number)ast

        dump_indent(indent)
        fmt.printfln("  value = %v", number.value)

    case .String:
        str := cast(^Ast_String)ast

        dump_indent(indent)
        fmt.printfln("  value = %v", str.value)

    case .Bool:
        boolean := cast(^Ast_Bool)ast

        dump_indent(indent)
        fmt.printfln("  value = %v", boolean.value)

    case .Nil:
        ast_nil := cast(^Ast_Nil)ast

        dump_indent(indent)
        fmt.println("  nil")

    case .Negate:
        operator := cast(^Ast_Unary_Operator)ast

        dump_indent(indent)
        fmt.print("  operand = ")
        dump_ast(operator.operand, indent + 1)

    case .Plus: fallthrough
    case .Minus: fallthrough
    case .Times: fallthrough
    case .Divide: fallthrough
    case .Equal: fallthrough
    case .Less: fallthrough
    case .LessEqual: fallthrough
    case .Greater: fallthrough
    case .GreaterEqual:
        operator := cast(^Ast_Binary_Operator)ast

        dump_indent(indent)
        fmt.print("  left = ")
        dump_ast(operator.left, indent + 1)

        dump_indent(indent)
        fmt.print("  right = ")
        dump_ast(operator.right, indent + 1)

    case .Var:
        var := cast(^Ast_Var)ast

        dump_indent(indent)
        fmt.printfln("  name = %v", var.name)
    }
    dump_indent(indent)
    fmt.println(")")
}

Parser :: struct {
    using lexer: ^Lexer,

    // Allocator for AST nodes (almost surely a linear allocator). We use this when calling
    // `new` on an AST node and allow dynamic arrays and maps to use the context allocator
    // since they are unfriendly to linear allocators.
    ast_allocator: runtime.Allocator,

    scopes: [dynamic]^Ast_Scope,
}

// @Cleanup: I don't think we need parser.scopes if we have a parent on the Ast_Scopes...
delete_parser :: proc(parser: Parser) {
    delete(parser.scopes)
}

parse_all :: proc(parser: ^Parser) -> ^Ast_Scope {
    // @Cleanup: What scope?
    global_scope := new_ast_node(Ast_Scope, 0, 0, 0, 0, parser)
    append(&parser.scopes, global_scope)

    statement := parse_statement_or_scope(parser)
    for statement != nil {
        append(&global_scope.children, statement)
        statement = parse_statement_or_scope(parser)
    }

    pop(&parser.scopes)
    return global_scope
}

parse_statement_or_scope :: proc(parser: ^Parser) -> ^Ast {
    line_start := parser.line
    char_start := parser.char

    ast: ^Ast

    token := peek_token(parser.lexer)

    if token.type == .Eof {
        return nil
    }

    if token.type == .LeftBrace {
        // This is a scope.

        lex_token(parser.lexer) // Consume the left brace.
        // @Cleanup: What scope?
        scope := new_ast_node(Ast_Scope, 0, 0, 0, 0, parser)
        scope.parent = parser.scopes[len(parser.scopes) - 1]
        append(&parser.scopes, scope)

        token := peek_token(parser.lexer)
        for token.type != .RightBrace {
            statement := parse_statement_or_scope(parser)
            append(&scope.children, statement)
            token = peek_token(parser.lexer)
        }

        lex_token(parser.lexer) // Consume the right brace.

        pop(&parser.scopes)
        return scope
    }

    #partial switch token.type {
        case .Print:
            lex_token(parser.lexer) // Consume the 'print' keyword.
            expr := parse_expression(parser)

            print := new_ast_node(Ast_Print, token.code_index, expr.end_code_index, line_start, char_start, parser)
            print.expr = expr

            ast = cast(^Ast)print

        case .Var:
            lex_token(parser.lexer) // Consume the 'var' keyword.
            name := expect_token(parser.lexer, .Identifier)
            next := peek_token(parser.lexer)

            value: ^Ast_Expression
            if next.type == .Equal {
                lex_token(parser.lexer) // Consume the 'equals'.
                value = parse_expression(parser)
            } else {
                value = cast(^Ast_Expression)new_ast_node(Ast_Nil, name.code_index,  name.code_index + len(name.value), line_start, char_start, parser)
            }

            var_def := new_ast_node(Ast_Var_Definition, token.code_index, value.end_code_index, line_start, char_start, parser)
            var_def.name = name.value
            var_def.value = value

            ast = cast(^Ast)var_def

        case:
            ast = cast(^Ast)parse_expression(parser)
    }

    expect_token(parser.lexer, .Semicolon, ";")
    return ast
}

MIN_BINDING_POWER :: 5 // @Volatile: Must be updated with binding_powers.
binding_powers := map[Token_Type]int{
    .Less = 5,
    .LessEqual = 5,
    .Greater = 5,
    .GreaterEqual = 5,
    .EqualEqual = 6,
    .Plus = 10,
    .Minus = 10,
    .Star = 20,
    .Slash = 20,
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
        #partial switch maybe_operator.type {
        case .Plus:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Plus, left.start_code_index, right.end_code_index, line_start, char_start, parser)
        case .Minus:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Minus, left.start_code_index, right.end_code_index, line_start, char_start, parser)
        case .Star:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Times, left.start_code_index, right.end_code_index, line_start, char_start, parser)
        case .Slash:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Divide, left.start_code_index, right.end_code_index, line_start, char_start, parser)
        case .EqualEqual:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Equal, left.start_code_index, right.end_code_index, line_start, char_start, parser)
        case .Less:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Less, left.start_code_index, right.end_code_index, line_start, char_start, parser)
        case .LessEqual:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_LessEqual, left.start_code_index, right.end_code_index, line_start, char_start, parser)
        case .Greater:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Greater, left.start_code_index, right.end_code_index, line_start, char_start, parser)
        case .GreaterEqual:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_GreaterEqual, left.start_code_index, right.end_code_index, line_start, char_start, parser)
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

    token := lex_token(parser.lexer)

    if token.type == .Eof {
        return nil
    }

    is_negate := false
    if token.type == .Minus {
        is_negate = true
        token = lex_token(parser.lexer)
    }

    expr: ^Ast_Expression
    if token.type == .LeftParen {
        expr = parse_expression(parser)
        expect_token(parser.lexer, .RightParen, ")")
    } else {
        #partial switch token.type {
        case .Number:
            ast := new_ast_node(Ast_Number, token.code_index, token.code_index + len(token.value), line_start, char_start, parser)

            number, number_ok := strconv.parse_f32(token.value)
            assert(number_ok)
            ast.value = number
            expr = cast(^Ast_Expression)ast

        case .String:
            ast := new_ast_node(Ast_String, token.code_index, token.code_index + len(token.value) + 2, line_start, char_start, parser)
            ast.value = token.value
            expr = cast(^Ast_Expression)ast

        case .True:
            ast := new_ast_node(Ast_Bool, token.code_index, token.code_index + 4, line_start, char_start, parser)
            ast.value = true
            expr = cast(^Ast_Expression)ast

        case .False:
            ast := new_ast_node(Ast_Bool, token.code_index, token.code_index + 5,  line_start, char_start, parser)
            ast.value = false
            expr = cast(^Ast_Expression)ast

        case .Nil:
            ast := new_ast_node(Ast_Nil, token.code_index, token.code_index + 3,  line_start, char_start, parser)
            expr = cast(^Ast_Expression)ast

        case .Identifier:
            // @Incomplete: Parse function calls.
            ast := new_ast_node(Ast_Var, token.code_index, token.code_index + len(token.value),  line_start, char_start, parser)
            ast.name = token.value
            expr = cast(^Ast_Expression)ast

        case:
            report_internal_error("Unsupported token type %v when parsing an expression leaf.", token.type)
        }
    }

    if is_negate {
        negate := new_ast_node(Ast_Negate, token.code_index, expr.end_code_index, line_start, char_start, parser)
        negate.operand = expr
        return negate
    } else {
        return expr
    }
}
