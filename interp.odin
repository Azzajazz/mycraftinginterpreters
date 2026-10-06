package lox

import "base:runtime"

import "core:fmt"
import "core:os"
import "core:strings"

Value :: union {
    string,
    f32,
    bool,
    ^Ast_Function,
}

get_value_type_name :: proc(value: Value) -> string {
    switch _ in value {
    case nil:           return "nil"
    case string:        return "string"
    case f32:           return "number"
    case bool:          return "bool"
    case ^Ast_Function: return "function"
    }

    unreachable()
}

Environment :: struct {
    parent: ^Environment,
    variables: map[string]Value,
    functions: map[string]^Ast_Function,
}

delete_environment :: proc(env: ^Environment) {
    delete(env.variables)
    delete(env.functions)
    free(env)
}

Interp :: struct {
    // @Temporary: We need the code for each file to live somewhere so that error messages make sense.
    // It's either here or on every AST node.
    // Eventually we will have to support multiple files, so this will have to change.
    file: ^Lox_File,

    current_environment: ^Environment,
    scope_envs: map[^Ast_Scope]^Environment,

    // @Temporary? Linear allocator to store runtime constructed strings.
    strings_allocator: runtime.Allocator,
}

delete_interp :: proc(interp: ^Interp) {
    delete(interp.scope_envs)
}

is_in_global_scope :: proc(interp: ^Interp) -> bool {
    return interp.current_environment.parent == nil
}

Lexical_Span :: struct {
    start: int,
    end: int,
}

// :SpansForErrors
// @Cleanup: Maybe introduce some concept of spans?
report_error :: proc(file: ^Lox_File, span: Lexical_Span, format: string, args: ..any) {
    line_number, char_number := get_line_and_char(file.code, span.start)
    fmt.eprintf("%v(%v:%v) Error: ", file.path, line_number + 1, char_number + 1)
    fmt.eprintfln(format, ..args)

    // @Cleanup: Ewwwwwwww.
    first_line_start_index := span.start
    for first_line_start_index > 0 && file.code[first_line_start_index - 1] != '\n' {
        first_line_start_index -= 1
    }

    last_line_end_index := span.end
    for last_line_end_index < len(file.code) && file.code[last_line_end_index] != '\n' {
        last_line_end_index += 1
    }

    code_span := file.code[first_line_start_index:last_line_end_index]
    code_index_cursor := span.start
    
    // First line.
    line, line_ok := strings.split_lines_iterator(&code_span)
    assert(line_ok)
    fmt.eprintfln("    %v", line)
    fmt.eprint("    ")

    padding := code_index_cursor - first_line_start_index
    end_index_relative_to_line := span.end - first_line_start_index
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
        for _ in 0..<min(span.end - code_index_cursor, len(line)) {
            fmt.eprint("^")
        }
        fmt.eprintln()

        code_index_cursor += len(line) + 1 // + 1 to account for the newline.
    }

    os.exit(1)
}

evaluate :: proc(interp: ^Interp, ast: ^Ast) -> (return_value: Value, did_return: bool) {
    #partial switch ast.type {
    case .Function:
        function := cast(^Ast_Function)ast

        interp.current_environment.functions[function.name] = function
        interp.scope_envs[function.enclosing_scope] = interp.current_environment

    case .Scope:
        scope := cast(^Ast_Scope)ast

        env := new(Environment)
        env.parent = interp.current_environment
        interp.current_environment = env
        defer {
            env = interp.current_environment
            interp.current_environment = env.parent
            delete_environment(env)
        }

        for child in scope.children {
            return_value, did_return = evaluate(interp, child)
            if did_return do return return_value, did_return
        }

    case .If:
        ast_if := cast(^Ast_If)ast

        condition_value := evaluate_expression(interp, ast_if.condition)

        condition_is_true: bool
        #partial switch v in condition_value {
        case bool:
            condition_is_true = v
        case nil:
            condition_is_true = false
        case:
            condition_is_true = true
        }

        value: Value
        returned: bool
        if condition_is_true {
            value, returned = evaluate(interp, ast_if.if_true)

        } else if ast_if.if_false != nil {
            value, returned = evaluate(interp, ast_if.if_false)
        }
        if returned do return value, returned
    
    case .Print:
        ast_print := cast(^Ast_Print)ast
        value := evaluate_expression(interp, ast_print.expr)
        switch v in value {
            case nil:
                fmt.println("nil")
            case f32, string, bool:
                fmt.println(v)
            case ^Ast_Function:
                fmt.printfln("<fn %v>", v.name)
        }

    case .VarDefinition:
        ast_var_def := cast(^Ast_Var_Definition)ast
        value := evaluate_expression(interp, ast_var_def.value, ast_var_def.name)
        interp.current_environment.variables[ast_var_def.name] = value

    case .Return:
        ast_return := cast(^Ast_Return)ast

        expr := evaluate_expression(interp, ast_return.expr)
        return expr, true

    case .Assign:
        ast_assign := cast(^Ast_Assign)ast

        value := evaluate_expression(interp, ast_assign.value)
        was_set := set_value(interp, ast_assign.name, value)
        assert(was_set)

    case:
        if is_expression(ast) {
            evaluate_expression(interp, cast(^Ast_Expression)ast)
        } else {
            report_internal_error("Could not evaluate AST of type %v!", ast.type)
        }

    }

    return Value{}, false
}

evaluate_expression :: proc(interp: ^Interp, expr: ^Ast_Expression, initialized_name := "") -> Value {
    assert(is_expression(expr))
    #partial switch expr.type {
        case .Number:
            ast_number := cast(^Ast_Number)expr
            return ast_number.value

        case .String:
            ast_string := cast(^Ast_String)expr
            return ast_string.value

        case .Bool:
            ast_bool := cast(^Ast_Bool)expr
            return ast_bool.value

        case .Nil:
            return nil

        case .Negate:
            ast_negate := cast(^Ast_Negate)expr
            operand := evaluate_expression(interp, ast_negate.operand)

            op, op_is_num := operand.(f32)

            if !op_is_num {
                report_error(interp.file, expr.span, "The negation operator '-' can only be applied to a 'number'. Here, the argument has type '%v'.", get_value_type_name(operand))
            }

            return -op

        case .Plus:
            ast_plus := cast(^Ast_Plus)expr
            left := evaluate_expression(interp, ast_plus.left)
            right := evaluate_expression(interp, ast_plus.right)

            #partial switch l in left {
            case f32:
                if r, r_is_num := right.(f32); r_is_num {
                    return l + r
                }

            case string:
                if r, r_is_string := right.(string); r_is_string {
                    new_string := strings.concatenate([]string{l, r}, interp.strings_allocator)
                    return new_string
                }
            }

            report_error(interp.file, expr.span, "'+' can only be applied to two 'number's or two 'string's. Here, the left operand has type '%v' and the right operand has type '%v'.", get_value_type_name(left), get_value_type_name(right))

        case .Times:
            ast_times := cast(^Ast_Times)expr
            left := evaluate_expression(interp, ast_times.left)
            right := evaluate_expression(interp, ast_times.right)

            // @Incomplete: Implement multiplication for more types.
            left_num, left_is_num := left.(f32)
            right_num, right_is_num := right.(f32)
            if !left_is_num || !right_is_num {
                report_error(interp.file, expr.span, "'*' can only be applied to two 'number's. Here, the left operand has type '%v' and the right operand has type '%v'.", get_value_type_name(left), get_value_type_name(right))
            }

            return left_num * right_num

        case .Divide:
            ast_divide := cast(^Ast_Divide)expr
            left := evaluate_expression(interp, ast_divide.left)
            right := evaluate_expression(interp, ast_divide.right)

            // @Incomplete: Implement division for more types.
            left_num, left_is_num := left.(f32)
            right_num, right_is_num := right.(f32)
            if !left_is_num || !right_is_num {
                report_error(interp.file, expr.span, "'/' can only be applied to two 'number's. Here, the left operand has type '%v' and the right operand has type '%v'.", get_value_type_name(left), get_value_type_name(right))
            }

            return left_num / right_num

        case .Minus:
            ast_minus := cast(^Ast_Minus)expr
            left := evaluate_expression(interp, ast_minus.left)
            right := evaluate_expression(interp, ast_minus.right)

            // @Incomplete: Implement subtraction for more types.
            left_num, left_is_num := left.(f32)
            right_num, right_is_num := right.(f32)
            if !left_is_num || !right_is_num {
                report_internal_error("Subtraction is only implemented for number types.")
            }

            return left_num - right_num

        case .Equal:
            ast_equal := cast(^Ast_Equal)expr
            left := evaluate_expression(interp, ast_equal.left)
            right := evaluate_expression(interp, ast_equal.right)

            switch l in left {
            case nil:
                return right == nil

            case f32:
                r, r_is_num := right.(f32)
                return r_is_num && l == r

            case string:
                r, r_is_string := right.(string)
                return r_is_string && l == r

            case bool:
                r, r_is_bool := right.(bool)
                return r_is_bool && l == r

            case ^Ast_Function:
                // @Audit: When does it make sense to compare functions equal?
                return false
            }

        case .Less:
            ast_less := cast(^Ast_Less)expr
            left := evaluate_expression(interp, ast_less.left)
            right := evaluate_expression(interp, ast_less.right)

            left_num, left_is_num := left.(f32)
            right_num, right_is_num := right.(f32)
            if !left_is_num || !right_is_num {
                report_error(interp.file, expr.span, "'<' can only be applied to two 'number's. Here, the left operand has type '%v' and the right operand has type '%v'.", get_value_type_name(left), get_value_type_name(right))
            }

            return left_num < right_num

        case .LessEqual:
            ast_less_equal := cast(^Ast_LessEqual)expr
            left := evaluate_expression(interp, ast_less_equal.left)
            right := evaluate_expression(interp, ast_less_equal.right)

            left_num, left_is_num := left.(f32)
            right_num, right_is_num := right.(f32)
            if !left_is_num || !right_is_num {
                report_error(interp.file, expr.span, "'<=' can only be applied to two 'number's. Here, the left operand has type '%v' and the right operand has type '%v'.", get_value_type_name(left), get_value_type_name(right))
            }

            return left_num <= right_num

        case .Greater:
            ast_greater := cast(^Ast_Greater)expr
            left := evaluate_expression(interp, ast_greater.left)
            right := evaluate_expression(interp, ast_greater.right)

            left_num, left_is_num := left.(f32)
            right_num, right_is_num := right.(f32)
            if !left_is_num || !right_is_num {
                report_error(interp.file, expr.span, "'>' can only be applied to two 'number's. Here, the left operand has type '%v' and the right operand has type '%v'.", get_value_type_name(left), get_value_type_name(right))
            }

            return left_num > right_num

        case .GreaterEqual:
            ast_greater_equal := cast(^Ast_GreaterEqual)expr
            left := evaluate_expression(interp, ast_greater_equal.left)
            right := evaluate_expression(interp, ast_greater_equal.right)

            left_num, left_is_num := left.(f32)
            right_num, right_is_num := right.(f32)
            if !left_is_num || !right_is_num {
                report_error(interp.file, expr.span, "'>=' can only be applied to two 'number's. Here, the left operand has type '%v' and the right operand has type '%v'.", get_value_type_name(left), get_value_type_name(right))
            }

            return left_num >= right_num

        case .Var:
            ast_var := cast(^Ast_Var)expr
            value, value_found := lookup_identifier(interp, ast_var.name, ast_var.hops_to_resolve)
            assert(value_found)
            
            return value

        case .Call:
            ast_call := cast(^Ast_Call)expr

            identifier_value := evaluate_expression(interp, ast_call.identifier_expr)
            function, is_function := identifier_value.(^Ast_Function)
            if !is_function {
                report_error(interp.file, expr.span, "Attempt to call an expression that is not a function.")
            }

            if len(ast_call.args) != len(function.params) {
                report_error(interp.file, expr.span, "Function was called with the incorrect number of arguments. Expected %v arguments, got %v.", len(function.params), len(ast_call.args))
            }

            old_env := interp.current_environment

            env := new(Environment)
            env.parent = interp.scope_envs[function.enclosing_scope]

            // Bind the values of the arguments to the parameters in the body scope.
            for i in 0..<len(ast_call.args) {
                value := evaluate_expression(interp, ast_call.args[i])
                env.variables[function.params[i]] = value
            }

            interp.current_environment = env

            defer {
                env = interp.current_environment
                interp.current_environment = old_env
                delete_environment(env)
            }
            
            for child in function.body.children {
                value, returned := evaluate(interp, child)
                if returned do return value
            }

            return nil

        case:
            report_internal_error("AST type %v is not an expression type.", expr.type)
    }

    unreachable()
}

set_value :: proc(interp: ^Interp, name: string, value: Value) -> bool {
    env := interp.current_environment

    for env != nil {
        defer env = env.parent

        if name in env.variables {
            env.variables[name] = value
            return true
        }
    }

    return false
}

lookup_identifier :: proc(interp: ^Interp, name: string, hops: int) -> (value: Value, value_found: bool) {
    env := interp.current_environment
    for _ in 0..<hops {
        env = env.parent
    }

    value, value_found = env.variables[name]
    if value_found do return value, value_found

    value, value_found = env.functions[name]
    if value_found do return value, value_found

    return nil, false
}
