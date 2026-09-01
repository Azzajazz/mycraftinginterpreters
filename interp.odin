package lox

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
            // @Robustness: Error message here.
            assert(operand.type == .Number)
            return Value{type = .Number, value = {number = -operand.value.number}}

        case .Plus:
            ast_plus := cast(^Ast_Plus)expr
            left := evaluate_expression(interp, ast_plus.left)
            right := evaluate_expression(interp, ast_plus.right)
            // @Robustness @Incomplete: Error messages and support for string '+'.
            assert(left.type == .Number)
            assert(right.type == .Number)
            return Value{type = .Number, value = {number = left.value.number + right.value.number}}

        case .Times:
            ast_times := cast(^Ast_Times)expr
            left := evaluate_expression(interp, ast_times.left)
            right := evaluate_expression(interp, ast_times.right)
            // @Robustness @Incomplete: Error messages and support for string '+'.
            assert(left.type == .Number)
            assert(right.type == .Number)
            return Value{type = .Number, value = {number = left.value.number * right.value.number}}

        case .Minus:
            ast_minus := cast(^Ast_Minus)expr
            left := evaluate_expression(interp, ast_minus.left)
            right := evaluate_expression(interp, ast_minus.right)
            // @Robustness @Incomplete: Error messages and support for string '+'.
            assert(left.type == .Number)
            assert(right.type == .Number)
            return Value{type = .Number, value = {number = left.value.number - right.value.number}}

        case:
            panic("Ahhhhh!")
    }
}
