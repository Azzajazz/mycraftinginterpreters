package lox

import "core:fmt"
import "core:os"

Value_Type :: enum {
    String,
    Number,
}

Value :: struct {
    type: Value_Type,
    value: struct #raw_union {
        str: string,
        number: f32,
    },
}

Interp :: struct {
    variables: map[string]Value,
}

report_error :: proc(ast: Ast, format: string, args: ..any) {
    fmt.eprintf("%v(%v:%v) Error: ", ast.file_name, ast.line_start + 1, ast.char_start + 1)
    fmt.eprintfln(format, ..args)
    os.exit(1)
}

evaluate_expression :: proc(interp: ^Interp, expr: ^Ast_Expression) -> Value {
    #partial switch expr.type {
        case .Number:
            ast_number := cast(^Ast_Number)expr
            return Value{type = .Number, value = {number = ast_number.value}}

        case .String:
            ast_string := cast(^Ast_String)expr
            return Value{type = .String, value = {str = ast_string.value}}

        case .Negate:
            ast_negate := cast(^Ast_Negate)expr
            operand := evaluate_expression(interp, ast_negate.operand)

            if operand.type != .Number {
                report_error(expr, "The negation operator '-' can only be applied to numbers. This variable has type %v.", operand.type)
            }

            return Value{type = .Number, value = {number = -operand.value.number}}

        case .Plus:
            ast_plus := cast(^Ast_Plus)expr
            left := evaluate_expression(interp, ast_plus.left)
            right := evaluate_expression(interp, ast_plus.right)

            // @Incomplete: Implement addition for more types.
            if left.type != .Number || right.type != .Number {
                report_internal_error("Addition is only implemented for number types.")
            }

            return Value{type = .Number, value = {number = left.value.number + right.value.number}}

        case .Times:
            ast_times := cast(^Ast_Times)expr
            left := evaluate_expression(interp, ast_times.left)
            right := evaluate_expression(interp, ast_times.right)

            // @Incomplete: Implement multiplication for more types.
            if left.type != .Number || right.type != .Number {
                report_internal_error("Multiplication is only implemented for number types.")
            }

            return Value{type = .Number, value = {number = left.value.number * right.value.number}}

        case .Minus:
            ast_minus := cast(^Ast_Minus)expr
            left := evaluate_expression(interp, ast_minus.left)
            right := evaluate_expression(interp, ast_minus.right)

            // @Incomplete: Implement subtraction for more types.
            if left.type != .Number || right.type != .Number {
                report_internal_error("Subtraction is only implemented for number types.")
            }

            return Value{type = .Number, value = {number = left.value.number - right.value.number}}

        case:
            report_internal_error("AST type %v is not an expression type.", expr.type)
    }

    unreachable()
}
