package lox

import "base:runtime"

import "core:fmt"
import "core:os"
import "core:strings"

Value_Type :: enum {
    String,
    Number,
    Bool,
    Nil,
}

Value :: struct {
    type: Value_Type,
    value: struct #raw_union {
        str: string,
        number: f32,
        boolean: bool,
    },
}

Function_Info :: struct {
    ast: ^Ast_Function,
    enclosing_env: ^Environment,
}

Environment :: struct {
    parent: ^Environment,
    variables: map[string]Value,
    functions: map[string]Function_Info,
}

delete_environment :: proc(env: ^Environment) {
    delete(env.variables)
    delete(env.functions)
    free(env)
}

Interp :: struct {
    // @Temporary: We need the code for each file to live somewhere so that error messages make sense.
    // It'e either here or on every AST node.
    // Eventually we will have to support multiple files, so this will have to change.
    file_name: string,
    code: string,
    current_environment: ^Environment,

    // @Temporary? Linear allocator to store runtime constructed strings.
    strings_allocator: runtime.Allocator,
}

is_in_global_scope :: proc(interp: ^Interp) -> bool {
    return interp.current_environment.parent == nil
}

// :SpansForErrors
// @Cleanup: Maybe introduce some concept of spans?
report_error :: proc(file_name: string, code: string, span_start, span_end: int, format: string, args: ..any) {
    line_number, char_number := get_line_and_char(code, span_start)
    fmt.eprintf("%v(%v:%v) Error: ", file_name, line_number + 1, char_number + 1)
    fmt.eprintfln(format, ..args)

    // @Cleanup: Ewwwwwwww.
    first_line_start_index := span_start
    for first_line_start_index > 0 && code[first_line_start_index - 1] != '\n' {
        first_line_start_index -= 1
    }

    last_line_end_index := span_end
    for last_line_end_index < len(code) && code[last_line_end_index] != '\n' {
        last_line_end_index += 1
    }

    code_span := code[first_line_start_index:last_line_end_index]
    code_index_cursor := span_start
    
    // First line.
    line, line_ok := strings.split_lines_iterator(&code_span)
    assert(line_ok)
    fmt.eprintfln("    %v", line)
    fmt.eprint("    ")

    padding := code_index_cursor - first_line_start_index
    end_index_relative_to_line := span_end - first_line_start_index
    arrows := min(len(line), end_index_relative_to_line) - padding
    for _ in 0..<padding {
        fmt.eprint(" ")
    }
    for _ in 0..<arrows {
        fmt.eprint("^")
    }
    fmt.eprintln()

    code_index_cursor += arrows + 1 // + 1 to account for the newline.
    
    // The rest of the lines.
    for line in strings.split_lines_iterator(&code_span) {
        fmt.eprintfln("    %v", line)
        fmt.eprint("    ")
        for _ in 0..<min(span_end - code_index_cursor, len(line)) {
            fmt.eprint("^")
        }
        fmt.eprintln()

        code_index_cursor += len(line) + 1 // + 1 to account for the newline.
    }

    os.exit(1)
}

evaluate :: proc(interp: ^Interp, ast: ^Ast) {
    #partial switch ast.type {
    case .Scope:
        scope := cast(^Ast_Scope)ast

        env := new(Environment)
        env.parent = interp.current_environment
        interp.current_environment = env

        for child in scope.children {
            evaluate(interp, child)
        }

        env = interp.current_environment
        interp.current_environment = env.parent
        delete_environment(env)

    case .Function:
        function := cast(^Ast_Function)ast

        interp.current_environment.functions[function.name] = Function_Info{
            ast = function,
            enclosing_env = interp.current_environment,
        }
    
    case .Print:
        ast_print := cast(^Ast_Print)ast
        value := evaluate_expression(interp, ast_print.expr)
        switch value.type {
            case .Number:
                fmt.println(value.value.number)
            case .String:
                fmt.println(value.value.str)
            case .Bool:
                fmt.println(value.value.boolean)
            case .Nil:
                fmt.println("nil")
        }

    case .VarDefinition:
        ast_var_def := cast(^Ast_Var_Definition)ast
        value := evaluate_expression(interp, ast_var_def.value, ast_var_def.name)

        if !is_in_global_scope(interp) && ast_var_def.name in interp.current_environment.variables {
            report_error(interp.file_name, interp.code, ast.start_code_index, ast.end_code_index, "Cannot redefine a variable in a scope that is not the global scope.")
        } else {
            interp.current_environment.variables[ast_var_def.name] = value
        }

    case:
        if is_expression(ast) {
            evaluate_expression(interp, cast(^Ast_Expression)ast)
        } else {
            report_internal_error("Could not evaluate AST of type %v!", ast.type)
        }
    }
}

evaluate_expression :: proc(interp: ^Interp, expr: ^Ast_Expression, initialized_name := "") -> Value {
    assert(is_expression(expr))
    #partial switch expr.type {
        case .Number:
            ast_number := cast(^Ast_Number)expr
            return Value{type = .Number, value = {number = ast_number.value}}

        case .String:
            ast_string := cast(^Ast_String)expr
            return Value{type = .String, value = {str = ast_string.value}}

        case .Bool:
            ast_bool := cast(^Ast_Bool)expr
            return Value{type = .Bool, value = {boolean = ast_bool.value}}

        case .Nil:
            ast_nil := cast(^Ast_Nil)expr
            return Value{type = .Nil}

        case .Negate:
            ast_negate := cast(^Ast_Negate)expr
            operand := evaluate_expression(interp, ast_negate.operand)

            if operand.type != .Number {
                report_error(interp.file_name, interp.code, expr.start_code_index, expr.end_code_index, "The negation operator '-' can only be applied to numbers. This variable has type %v.", operand.type)
            }

            return Value{type = .Number, value = {number = -operand.value.number}}

        case .Plus:
            ast_plus := cast(^Ast_Plus)expr
            left := evaluate_expression(interp, ast_plus.left)
            right := evaluate_expression(interp, ast_plus.right)

            if left.type == .Number && right.type == .Number {
                return Value{type = .Number, value = {number = left.value.number + right.value.number}}
            } else if left.type == .String && right.type == .String {
                new_string := strings.concatenate([]string{left.value.str, right.value.str}, interp.strings_allocator)
                return Value{type = .String, value = {str = new_string}}
            } else {
                report_error(interp.file_name, interp.code, expr.start_code_index, expr.end_code_index, "'+' is defined only on two Strings or two Numbers. Here, the left operand has type %v and the right operand has type %v.", left.type, right.type)
            }

        case .Times:
            ast_times := cast(^Ast_Times)expr
            left := evaluate_expression(interp, ast_times.left)
            right := evaluate_expression(interp, ast_times.right)

            // @Incomplete: Implement multiplication for more types.
            if left.type != .Number || right.type != .Number {
                report_internal_error("Multiplication is only implemented for number types.")
            }

            return Value{type = .Number, value = {number = left.value.number * right.value.number}}

        case .Divide:
            ast_divide := cast(^Ast_Divide)expr
            left := evaluate_expression(interp, ast_divide.left)
            right := evaluate_expression(interp, ast_divide.right)

            // @Incomplete: Implement multiplication for more types.
            if left.type != .Number || right.type != .Number {
                report_internal_error("Division is only implemented for number types.")
            }

            return Value{type = .Number, value = {number = left.value.number / right.value.number}}

        case .Minus:
            ast_minus := cast(^Ast_Minus)expr
            left := evaluate_expression(interp, ast_minus.left)
            right := evaluate_expression(interp, ast_minus.right)

            // @Incomplete: Implement subtraction for more types.
            if left.type != .Number || right.type != .Number {
                report_internal_error("Subtraction is only implemented for number types.")
            }

            return Value{type = .Number, value = {number = left.value.number - right.value.number}}

        case .Equal:
            ast_equal := cast(^Ast_Equal)expr
            left := evaluate_expression(interp, ast_equal.left)
            right := evaluate_expression(interp, ast_equal.right)

            if left.type != right.type {
                report_error(interp.file_name, interp.code, expr.start_code_index, expr.end_code_index, "'==' is defined only when the two expressions are the same type. Here, the left operand has type %v and the right operand has type %v.", left.type, right.type)
            }

            switch left.type {
            case .Number:
                return Value{type = .Bool, value = {boolean = left.value.number == right.value.number}}
            case .String:
                return Value{type = .Bool, value = {boolean = left.value.str == right.value.str}}
            case .Bool:
                return Value{type = .Bool, value = {boolean = left.value.boolean == right.value.boolean}}
            case .Nil:
                return Value{type = .Bool, value = {boolean = true}}
            }

        case .Less:
            ast_less := cast(^Ast_Less)expr
            left := evaluate_expression(interp, ast_less.left)
            right := evaluate_expression(interp, ast_less.right)

            if left.type != .Number || right.type != .Number {
                report_error(interp.file_name, interp.code, expr.start_code_index, expr.end_code_index, "'<' is defined only on two Numbers. Here, the left operand has type %v and the right operand has type %v.", left.type, right.type)
            }

            return Value{type = .Bool, value = {boolean = left.value.number < right.value.number}}

        case .LessEqual:
            ast_less_equal := cast(^Ast_LessEqual)expr
            left := evaluate_expression(interp, ast_less_equal.left)
            right := evaluate_expression(interp, ast_less_equal.right)

            // @Incomplete: Implement subtraction for more types.
            if left.type != .Number || right.type != .Number {
                report_error(interp.file_name, interp.code, expr.start_code_index, expr.end_code_index, "'<=' is defined only on two Numbers. Here, the left operand has type %v and the right operand has type %v.", left.type, right.type)
            }

            return Value{type = .Bool, value = {boolean = left.value.number <= right.value.number}}

        case .Greater:
            ast_greater := cast(^Ast_Greater)expr
            left := evaluate_expression(interp, ast_greater.left)
            right := evaluate_expression(interp, ast_greater.right)

            // @Incomplete: Implement subtraction for more types.
            if left.type != .Number || right.type != .Number {
                report_error(interp.file_name, interp.code, expr.start_code_index, expr.end_code_index, "'>' is defined only on two Numbers. Here, the left operand has type %v and the right operand has type %v.", left.type, right.type)
            }

            return Value{type = .Bool, value = {boolean = left.value.number > right.value.number}}

        case .GreaterEqual:
            ast_greater_equal := cast(^Ast_GreaterEqual)expr
            left := evaluate_expression(interp, ast_greater_equal.left)
            right := evaluate_expression(interp, ast_greater_equal.right)

            // @Incomplete: Implement subtraction for more types.
            if left.type != .Number || right.type != .Number {
                report_error(interp.file_name, interp.code, expr.start_code_index, expr.end_code_index, "'>=' is defined only on two Numbers. Here, the left operand has type %v and the right operand has type %v.", left.type, right.type)
            }

            return Value{type = .Bool, value = {boolean = left.value.number >= right.value.number}}

        case .Var:
            ast_var := cast(^Ast_Var)expr
            if !is_in_global_scope(interp) && ast_var.name == initialized_name {
                report_error(interp.file_name, interp.code, expr.start_code_index, expr.end_code_index, "Cannot use a local variable in its own initializer.")
            } else {
                value, value_found := resolve_variable_value(interp, ast_var.name)
                
                if !value_found {
                    report_error(interp.file_name, interp.code, expr.start_code_index, expr.end_code_index, "Variable %v was used, but it hasn't been defined.", ast_var.name)
                }
                return value
            }

        case .Call:
            ast_call := cast(^Ast_Call)expr

            function, function_found := resolve_function(interp, ast_call.name)
            if !function_found {
                report_error(interp.file_name, interp.code, expr.start_code_index, expr.end_code_index, "Function %v was called, but it hasn't been defined.", ast_call.name)
            }

            if len(ast_call.args) != len(function.ast.params) {
                report_error(interp.file_name, interp.code, expr.start_code_index, expr.end_code_index, "Function %v was called with the incorrect number of arguments. Expected %v arguments, got %v.", ast_call.name, len(function.ast.params), len(ast_call.args))
            }

            old_env := interp.current_environment

            // @Incomplete: Parameter bindings.
            // @Copy-paste from case .Scope in evaluate()
            env := new(Environment)
            env.parent = function.enclosing_env 
            interp.current_environment = env

            for child in function.ast.body.children {
                evaluate(interp, child)
            }

            env = interp.current_environment
            interp.current_environment = old_env
            delete_environment(env)
            
            // @Incomplete: Return values.
            return Value{type = .Nil}

        case:
            report_internal_error("AST type %v is not an expression type.", expr.type)
    }

    unreachable()
}

resolve_variable_value :: proc(interp: ^Interp, name: string) -> (value: Value, found: bool) {
    env := interp.current_environment

    for env != nil {
        defer env = env.parent

        value, found = env.variables[name]

        if found {
            return value, found
        }
    }

    return Value{}, false
}

resolve_function :: proc(interp: ^Interp, name: string) -> (function: Function_Info, found: bool) {
    env := interp.current_environment

    for env != nil {
        defer env = env.parent

        function, found = env.functions[name]

        if found {
            return function, found
        }
    }

    return Function_Info{}, false
}
