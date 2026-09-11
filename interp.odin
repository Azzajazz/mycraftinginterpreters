package lox

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

Interp :: struct {
    // @Temporary: We need the code for each file to live somewhere so that error messages make sense.
    // It'e either here or on every AST node.
    // Eventually we will have to support multiple files, so this will have to change.
    code: string,
    variables: [dynamic]map[string]Value,
}

delete_interp :: proc(interp: Interp) {
    delete(interp.variables)
}

is_in_global_scope :: proc(interp: ^Interp) -> bool {
    return len(interp.variables) == 1
}

report_error :: proc(code: string, ast: ^Ast, format: string, args: ..any) {
    line_number, char_number := get_line_and_char(code, ast.start_code_index)
    fmt.eprintf("%v(%v:%v) Error: ", ast.file_name, line_number + 1, char_number + 1)
    fmt.eprintfln(format, ..args)

    // @Cleanup: Ewwwwwwww.
    first_line_start_index := ast.start_code_index
    for first_line_start_index > 0 && code[first_line_start_index - 1] != '\n' {
        first_line_start_index -= 1
    }

    last_line_end_index := ast.end_code_index
    for last_line_end_index < len(code) && code[last_line_end_index] != '\n' {
        last_line_end_index += 1
    }

    code_span := code[first_line_start_index:last_line_end_index]
    code_index_cursor := ast.start_code_index
    
    // First line.
    line, line_ok := strings.split_lines_iterator(&code_span)
    assert(line_ok)
    fmt.eprintfln("    %v", line)
    fmt.eprint("    ")

    padding := code_index_cursor - first_line_start_index
    end_index_relative_to_line := ast.end_code_index - first_line_start_index
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
        for _ in 0..<min(ast.end_code_index - code_index_cursor, len(line)) {
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

        append(&interp.variables, nil)

        for child in scope.children {
            evaluate(interp, child)
        }

        var_map := pop(&interp.variables)
        delete(var_map)
    
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
        scoped_variables := &interp.variables[len(interp.variables) - 1]

        if !is_in_global_scope(interp) && ast_var_def.name in scoped_variables {
            report_error(interp.code, ast, "Cannot redefine a variable in a scope that is not the global scope.")
        } else {
            scoped_variables[ast_var_def.name] = value
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
                report_error(interp.code, expr, "The negation operator '-' can only be applied to numbers. This variable has type %v.", operand.type)
            }

            return Value{type = .Number, value = {number = -operand.value.number}}

        case .Plus:
            ast_plus := cast(^Ast_Plus)expr
            left := evaluate_expression(interp, ast_plus.left)
            right := evaluate_expression(interp, ast_plus.right)

            if left.type == .Number && right.type == .Number {
                return Value{type = .Number, value = {number = left.value.number + right.value.number}}
            } else if left.type == .String && right.type == .String {
                new_string := strings.concatenate([]string{left.value.str, right.value.str})
                return Value{type = .String, value = {str = new_string}}
            } else {
                report_error(interp.code, expr, "'+' is defined only on two Strings or two Numbers. Here, the left operand has type %v and the right operand has type %v.", left.type, right.type)
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
                report_error(interp.code, expr, "'==' is defined only when the two expressions are the same type. Here, the left operand has type %v and the right operand has type %v.", left.type, right.type)
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
                report_error(interp.code, expr, "'<' is defined only on two Numbers. Here, the left operand has type %v and the right operand has type %v.", left.type, right.type)
            }

            return Value{type = .Bool, value = {boolean = left.value.number < right.value.number}}

        case .LessEqual:
            ast_less_equal := cast(^Ast_LessEqual)expr
            left := evaluate_expression(interp, ast_less_equal.left)
            right := evaluate_expression(interp, ast_less_equal.right)

            // @Incomplete: Implement subtraction for more types.
            if left.type != .Number || right.type != .Number {
                report_error(interp.code, expr, "'<=' is defined only on two Numbers. Here, the left operand has type %v and the right operand has type %v.", left.type, right.type)
            }

            return Value{type = .Bool, value = {boolean = left.value.number <= right.value.number}}

        case .Greater:
            ast_greater := cast(^Ast_Greater)expr
            left := evaluate_expression(interp, ast_greater.left)
            right := evaluate_expression(interp, ast_greater.right)

            // @Incomplete: Implement subtraction for more types.
            if left.type != .Number || right.type != .Number {
                report_error(interp.code, expr, "'>' is defined only on two Numbers. Here, the left operand has type %v and the right operand has type %v.", left.type, right.type)
            }

            return Value{type = .Bool, value = {boolean = left.value.number > right.value.number}}

        case .GreaterEqual:
            ast_greater_equal := cast(^Ast_GreaterEqual)expr
            left := evaluate_expression(interp, ast_greater_equal.left)
            right := evaluate_expression(interp, ast_greater_equal.right)

            // @Incomplete: Implement subtraction for more types.
            if left.type != .Number || right.type != .Number {
                report_error(interp.code, expr, "'>=' is defined only on two Numbers. Here, the left operand has type %v and the right operand has type %v.", left.type, right.type)
            }

            return Value{type = .Bool, value = {boolean = left.value.number >= right.value.number}}

        case .Var:
            ast_var := cast(^Ast_Var)expr
            if !is_in_global_scope(interp) && ast_var.name == initialized_name {
                report_error(interp.code, expr, "Cannot use a local variable in its own initializer.")
            } else {
                value, value_found := resolve_variable_value(interp, ast_var.name)
                
                if !value_found {
                    report_error(interp.code, expr, "Variable %v was used, but it hasn't been defined.", ast_var.name)
                }
                return value
            }

        case:
            report_internal_error("AST type %v is not an expression type.", expr.type)
    }

    unreachable()
}

resolve_variable_value :: proc(interp: ^Interp, name: string) -> (value: Value, found: bool) {
    #reverse for variables in interp.variables {
        value, found = variables[name]

        if found {
            return value, found
        }
    }

    return Value{}, false
}
