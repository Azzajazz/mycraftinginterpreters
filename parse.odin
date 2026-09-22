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
    // Declarations that are not statements.
    Scope,
    Function,

    // Statements that are not expressions.
    Print,
    VarDefinition,
    Return,

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
    Call,
}

Ast :: struct {
    type: Ast_Type,

    file_name: string,

    start_code_index: int,
    end_code_index: int,
}

Ast_Scope :: struct {
    using ast: Ast,

    parent: ^Ast_Scope,
    // @Memory @Cleanup :DynamicArrayInArena
    children: [dynamic]^Ast,
}

Ast_Function :: struct {
    using ast: Ast,

    name: string,
    // @Memory @Cleanup :DynamicArrayInArena
    params: [dynamic]string,
    body: ^Ast_Scope,
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

Ast_Return :: struct {
    using stmt: Ast_Statement,

    expr: ^Ast_Expression,
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

Ast_Call :: struct {
    using expr: Ast_Expression,

    name: string,
    // @Memory @Cleanup :DynamicArrayInArena
    args: [dynamic]^Ast_Expression,
}

ast_types := map[typeid]Ast_Type {
    Ast_Scope = .Scope,
    Ast_Function = .Function,
    Ast_Print = .Print,
    Ast_Var_Definition = .VarDefinition,
    Ast_Return = .Return,
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
    Ast_Call = .Call,
}

// @Volatile: Must be kept in sync with Ast_Type.
is_expression :: proc(ast: ^Ast) -> bool {
    expression_min := cast(int)Ast_Type.Number
    return cast(int)ast.type >= expression_min
}

new_ast_node :: proc($T: typeid, start_code_index, end_code_index: int, parser: ^Parser) -> ^T {
    ast := new(T, parser.ast_allocator)
    ast.type = ast_types[T]

    ast.file_name = parser.file.path

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

    // @Memory @Cleanup :DynamicArrayInArena
    when T == Ast_Function {
        ast.params.allocator = parser.ast_allocator
    }

    // @Memory @Cleanup :DynamicArrayInArena
    when T == Ast_Call {
        ast.args.allocator = parser.ast_allocator
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

    case .Function:
        function := cast(^Ast_Function)ast

        dump_indent(indent)
        fmt.printfln("  name = %v", function.name)

        dump_indent(indent)
        fmt.println("  params = [")

        for param in function.params {
            dump_indent(indent + 2)
            fmt.println(param)
        }

        dump_indent(indent)
        fmt.println("  ]")

        dump_indent(indent)
        fmt.print("  body = ")

        dump_ast(function.body, indent + 1)

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

    case .Return:
        ast_return := cast(^Ast_Return)ast

        dump_indent(indent)
        fmt.print("  expr = ")

        dump_ast(ast_return.expr, indent + 1)

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

    case .Call:
        call := cast(^Ast_Call)ast

        dump_indent(indent)
        fmt.printfln("  name = %v", call.name)

        dump_indent(indent)
        fmt.println("  args = [")

        for arg in call.args {
            dump_indent(indent + 2)
            fmt.println(arg)
        }

        dump_indent(indent)
        fmt.println("  ]")
    }
    dump_indent(indent)
    fmt.println(")")
}

Parser :: struct {
    file: ^LoxFile,

    tokens: []Token,
    token_index: int,

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

consume_token :: proc(parser: ^Parser) -> Token {
    if parser.token_index >= len(parser.tokens) {
        return Token{type = .Eof}
    }

    token := parser.tokens[parser.token_index]
    parser.token_index += 1
    return token
}

next_token :: proc(parser: ^Parser) -> Token {
    if parser.token_index >= len(parser.tokens) {
        return Token{type = .Eof}
    }

    return parser.tokens[parser.token_index]
}

// @Cleanup: Provide a message here instead of forcing it to conform to the
// "Expected x, but got y" format.
expect_token :: proc(parser: ^Parser, token_type: Token_Type, format: string, args: ..any) -> (token: Token, ok: bool) #optional_ok {
    token = consume_token(parser)

    if token.type != token_type {
        had_error = true
        report_lex_error(parser.file, token, format, ..args)

        return Token{}, false
    }

    return token, true
}

skip_to_token :: proc(parser: ^Parser, token_type: Token_Type) {
    for parser.token_index < len(parser.tokens) && parser.tokens[parser.token_index].type != token_type {
        parser.token_index += 1
    }
    parser.token_index += 1
}

parse_all :: proc(parser: ^Parser) -> ^Ast_Scope {
    // @Cleanup: What scope?
    global_scope := new_ast_node(Ast_Scope, 0, 0, parser)
    append(&parser.scopes, global_scope)

    decl := parse_declaration(parser)
    for decl != nil {
        append(&global_scope.children, decl)
        decl = parse_declaration(parser)
    }

    pop(&parser.scopes)
    return global_scope
}

parse_declaration :: proc(parser: ^Parser, return_is_valid := false) -> ^Ast {
    token := next_token(parser)

    if token.type == .Eof {
        return nil
    }

    #partial switch token.type {
    case .LeftBrace:
        consume_token(parser) // Consume the left brace.
        // @Cleanup: What scope?
        scope := new_ast_node(Ast_Scope, 0, 0, parser)
        scope.parent = parser.scopes[len(parser.scopes) - 1]
        append(&parser.scopes, scope)

        token := next_token(parser)
        for token.type != .RightBrace {
            if token.type == .Eof {
                // @Hack @Cleanup: We're using `scope` as the AST node here, for lack of something better.
                // This probably means we need a more general report_error function, or
                // at least separate report_interp_error and report_parse_error.
                report_error(parser.file, scope.start_code_index, scope.end_code_index, "Reached end of file while parsing a scope.")
            }

            decl := parse_declaration(parser, return_is_valid)
            append(&scope.children, decl)
            token = next_token(parser)
        }

        consume_token(parser) // Consume the right brace.

        pop(&parser.scopes)
        return scope

    case .Fun:
        consume_token(parser) // Consume the 'fun' keyword.
        name := expect_token(parser, .Identifier, "Function name must be a valid identifier.")

        function := new_ast_node(Ast_Function, token.code_index, name.code_index, parser)

        // @Cleanup: The error messages here aren't great...
        // Parse parameter list.
        parse_parameter_list(parser, function, &function.params)

        body := parse_declaration(parser, true)
        if body.type != .Scope {
            // @Crash: report_error exits the program. We should recover and continue parsing instead.
            report_error(parser.file, body.start_code_index, body.end_code_index, "Function body must be a scope.")
        }

        function.name = name.value
        function.body = cast(^Ast_Scope)body

        return function

    case:
        return parse_statement(parser, return_is_valid)
    }
}

parse_parameter_list :: proc(parser: ^Parser, ast: ^Ast, params: ^[dynamic]string) {
    parse_ok := true
    defer if !parse_ok {
        skip_to_token(parser, .RightParen)
    }

    _, parse_ok = expect_token(parser, .LeftParen, "Function parameters must begin with a '('.")
    if !parse_ok do return

    token := next_token(parser)
    if token.type != .RightParen {
        param: Token
        param, parse_ok = expect_token(parser, .Identifier, "Function parameters must be valid identifiers.")
        if !parse_ok do return
        append(params, param.value)

        token = next_token(parser)
        for token.type != .RightParen {
            if token.type == .Eof {
                report_error(parser.file, ast.start_code_index, ast.end_code_index, "Reached end of file while parsing a parameter list.")
            }

            _, parse_ok = expect_token(parser, .Comma, "Function parameters must be separated with a ','")
            if !parse_ok do return

        param, parse_ok = expect_token(parser, .Identifier, "Function parameters must be valid identifiers.")
            if !parse_ok do return
            append(params, param.value)

            token = next_token(parser)
        }
    }
    consume_token(parser) // Consume the right paren.
}

// :SpansForErrors
// @Cleanup: Introduce spans.
parse_argument_list :: proc(parser: ^Parser, span_start, span_end: int, args: ^[dynamic]^Ast_Expression) {
    parse_ok := true
    defer if !parse_ok {
        skip_to_token(parser, .RightParen)
    }

    _, parse_ok = expect_token(parser, .LeftParen, "Function calls must contain their arguments in '(' and ')'.")
    if !parse_ok do return


    token := next_token(parser)
    if token.type != .RightParen {
        expr := parse_expression(parser)
        if expr == nil {
            // @Cleanup: Recoverable parsing errors.
            report_error(parser.file, span_start, span_end, "Arguments to functions must be expressions.")
        }
        append(args, expr)

        token = next_token(parser)
        for token.type != .RightParen {
            if token.type == .Eof {
                // @Cleanup: Recoverable parsing errors.
                report_error(parser.file, span_start, span_end, "Reached end of file while parsing a parameter list.")
            }

            _, token_ok := expect_token(parser, .Comma, "Arguments in function calls must be separated by ','.") 
            if !token_ok do skip_to_token(parser, .Comma)

            expr := parse_expression(parser)
            if expr == nil {
                // @Cleanup: Recoverable parsing errors.
                report_error(parser.file, span_start, span_end, "Arguments to functions must be expressions.")
            }
            append(args, expr)

            token = next_token(parser)
        }
    }
    consume_token(parser) // Consume the right paren.
}

parse_statement :: proc(parser: ^Parser, return_is_valid := false) -> ^Ast {
    ast: ^Ast

    token := next_token(parser)

    #partial switch token.type {
        case .Print:
            consume_token(parser) // Consume the 'print' keyword.
            expr := parse_expression(parser)

            print := new_ast_node(Ast_Print, token.code_index, expr.end_code_index, parser)
            print.expr = expr

            ast = cast(^Ast)print

        case .Var:
            consume_token(parser) // Consume the 'var' keyword.
            name := expect_token(parser, .Identifier, "Variable names must be valid identifiers.")
            next := next_token(parser)

            value: ^Ast_Expression
            if next.type == .Equal {
                consume_token(parser) // Consume the 'equals'.
                value = parse_expression(parser)
            } else {
                value = cast(^Ast_Expression)new_ast_node(Ast_Nil, name.code_index,  name.code_index + len(name.value), parser)
            }

            var_def := new_ast_node(Ast_Var_Definition, token.code_index, value.end_code_index, parser)
            var_def.name = name.value
            var_def.value = value

            ast = cast(^Ast)var_def

        case .Return:
            consume_token(parser)
            expr := parse_expression(parser)

            if !return_is_valid {
                report_error(parser.file, token.code_index, expr.end_code_index, "Return statements can only be used in function scope.")
            }

            ast_return := new_ast_node(Ast_Return, token.code_index, expr.end_code_index, parser)
            ast_return.expr = expr

            ast = cast(^Ast)ast_return

        case:
            ast = cast(^Ast)parse_expression(parser)
    }

    expect_token(parser, .Semicolon, "Statements must be followed by a ';'.")
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
    left := parse_expression_leaf(parser)
    maybe_operator := next_token(parser)
    binding_power, has_binding := binding_powers[maybe_operator.type]

    for has_binding {
        consume_token(parser) // Actually consume the operator.
        
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
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Plus, left.start_code_index, right.end_code_index, parser)
        case .Minus:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Minus, left.start_code_index, right.end_code_index, parser)
        case .Star:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Times, left.start_code_index, right.end_code_index, parser)
        case .Slash:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Divide, left.start_code_index, right.end_code_index, parser)
        case .EqualEqual:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Equal, left.start_code_index, right.end_code_index, parser)
        case .Less:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Less, left.start_code_index, right.end_code_index, parser)
        case .LessEqual:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_LessEqual, left.start_code_index, right.end_code_index, parser)
        case .Greater:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_Greater, left.start_code_index, right.end_code_index, parser)
        case .GreaterEqual:
            ast_operator = cast(^Ast_Binary_Operator)new_ast_node(Ast_GreaterEqual, left.start_code_index, right.end_code_index, parser)
        }

        assert(ast_operator != nil)
        ast_operator.left = left
        ast_operator.right = right

        left = ast_operator

        maybe_operator = next_token(parser)
        binding_power, has_binding = binding_powers[maybe_operator.type]
    }

    return left
}

parse_expression_leaf :: proc(parser: ^Parser) -> ^Ast_Expression {
    token := consume_token(parser)

    if token.type == .Eof {
        return nil
    }

    is_negate := false
    if token.type == .Minus {
        is_negate = true
        token = consume_token(parser)
    }

    expr: ^Ast_Expression
    if token.type == .LeftParen {
        expr = parse_expression(parser)
        expect_token(parser, .RightParen, "Unmatched parentheses. Expected a ')'.")
    } else {
        #partial switch token.type {
        case .Number:
            ast := new_ast_node(Ast_Number, token.code_index, token.code_index + len(token.value), parser)

            number, number_ok := strconv.parse_f32(token.value)
            assert(number_ok)
            ast.value = number
            expr = cast(^Ast_Expression)ast

        case .String:
            ast := new_ast_node(Ast_String, token.code_index, token.code_index + len(token.value) + 2, parser)
            ast.value = token.value
            expr = cast(^Ast_Expression)ast

        case .True:
            ast := new_ast_node(Ast_Bool, token.code_index, token.code_index + 4, parser)
            ast.value = true
            expr = cast(^Ast_Expression)ast

        case .False:
            ast := new_ast_node(Ast_Bool, token.code_index, token.code_index + 5,  parser)
            ast.value = false
            expr = cast(^Ast_Expression)ast

        case .Nil:
            ast := new_ast_node(Ast_Nil, token.code_index, token.code_index + 3,  parser)
            expr = cast(^Ast_Expression)ast

        case .Identifier:
            next := next_token(parser)
            if next.type == .LeftParen {
                call := new_ast_node(Ast_Call, token.code_index, 0 /* To be filled in later */, parser)

                token_length := get_token_length(parser.file, token)
                parse_argument_list(parser, token.code_index, token.code_index + token_length, &call.args)

                // @Temporary @Hack.
                call.end_code_index = parser.tokens[parser.token_index].code_index
                call.name = token.value

                expr = cast(^Ast_Expression)call
            } else {
                ast := new_ast_node(Ast_Var, token.code_index, token.code_index + len(token.value),  parser)
                ast.name = token.value
                expr = cast(^Ast_Expression)ast
            }

        case:
            report_internal_error("Unsupported token type %v when parsing an expression leaf.", token.type)
        }
    }

    if is_negate {
        negate := new_ast_node(Ast_Negate, token.code_index, expr.end_code_index, parser)
        negate.operand = expr
        return negate
    } else {
        return expr
    }
}
