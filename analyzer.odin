package lox

import "core:fmt"

Scope_Info :: struct {
    // @Performance: Maybe a set here?
    defined_variables: [dynamic]string,
    defined_functions: [dynamic]string,

    is_function_scope: bool,
}

delete_scope_info :: proc(info: Scope_Info) {
    delete(info.defined_variables)
    delete(info.defined_functions)
}

Analyzer :: struct {
    file: ^Lox_File,
    scope_infos: [dynamic]Scope_Info,

    currently_defining: string,
}

delete_analyzer :: proc(analyzer: ^Analyzer) {
    for info in analyzer.scope_infos {
        delete_scope_info(info)
    }

    delete(analyzer.scope_infos)
}

get_current_scope_info :: proc(analyzer: ^Analyzer) -> ^Scope_Info {
    return &analyzer.scope_infos[len(analyzer.scope_infos) - 1]
}

add_scope_info :: proc(analyzer: ^Analyzer, is_function_scope: bool) {
    resize(&analyzer.scope_infos, len(analyzer.scope_infos) + 1)
    info := get_current_scope_info(analyzer)
    info.is_function_scope = is_function_scope
}

remove_scope_info :: proc(analyzer: ^Analyzer) {
    scope_info := pop(&analyzer.scope_infos)
    delete_scope_info(scope_info)
}

add_function_definition :: proc(analyzer: ^Analyzer, name: string) {
    info := get_current_scope_info(analyzer)
    append(&info.defined_functions, name)
}

add_variable_definition :: proc(analyzer: ^Analyzer, name: string) {
    info := get_current_scope_info(analyzer)
    append(&info.defined_variables, name)
}

analyze :: proc(analyzer: ^Analyzer, ast: ^Ast) {
    switch ast.type {
    case .Scope:
        ast_scope := cast(^Ast_Scope)ast

        add_scope_info(analyzer, false)
        defer remove_scope_info(analyzer)

        for child in ast_scope.children {
            analyze(analyzer, child)
        }

    case .Function:
        ast_function := cast(^Ast_Function)ast

        add_function_definition(analyzer, ast_function.name)

        add_scope_info(analyzer, true)
        defer remove_scope_info(analyzer)

        // Treat function parameters as declarations.
        for param in ast_function.params {
            add_variable_definition(analyzer, param)
        }

        for child in ast_function.body.children {
            analyze(analyzer, child)
        }

    case .VarDefinition:
        ast_vardef := cast(^Ast_Var_Definition)ast

        analyzer.currently_defining = ast_vardef.name
        analyze(analyzer, ast_vardef.value)
        analyzer.currently_defining = ""

        if len(analyzer.scope_infos) > 1 {
            // We are not in global scope, so redefinition is an error.
            info := get_current_scope_info(analyzer)

            for def in info.defined_variables {
                if def == ast_vardef.name {
                    report_error(analyzer.file, ast.span, "Cannot redefine a variable in a scope that is not the global scope.")
                }
            }
        }

        add_variable_definition(analyzer, ast_vardef.name)

    case .Print:
        ast_print := cast(^Ast_Print)ast

        analyze(analyzer, ast_print.expr)

    case .Var:
        ast_var := cast(^Ast_Var)ast

        // If we are using a variable in its own initializer and it's not in global scope,
        // then error.
        if len(analyzer.scope_infos) > 1 && analyzer.currently_defining == ast_var.name {
                report_error(analyzer.file, ast.span, "Cannot use a local variable in its own initializer.")
        }

        // Resolve native procedures.
        if ast_var.name == "clock" {
            break
        }

        hops, found := resolve(analyzer, ast_var.name)
        if !found {
            report_error(analyzer.file, ast.span, "Variable '%v' was used, but it hasn't been defined yet.", ast_var.name)
        }

        ast_var.hops_to_resolve = hops

    case .Call:
        ast_call := cast(^Ast_Call)ast

        analyze(analyzer, ast_call.identifier_expr)
        for arg in ast_call.args {
            analyze(analyzer, arg)
        }

    case .Negate: fallthrough
    case .Not:
        ast_op := cast(^Ast_Unary_Operator)ast

        analyze(analyzer, ast_op.operand)

    case .Plus: fallthrough
    case .Minus: fallthrough
    case .Times: fallthrough
    case .Divide: fallthrough
    case .NotEqual: fallthrough
    case .Equal: fallthrough
    case .Less: fallthrough
    case .LessEqual: fallthrough
    case .Greater: fallthrough
    case .GreaterEqual:
        ast_op := cast(^Ast_Binary_Operator)ast

        analyze(analyzer, ast_op.left)
        analyze(analyzer, ast_op.right)

    case .Number: // Ignore
    case .Bool:   // Ignore
    case .String: // Ignore
    case .Nil:    // Ignore

    case .If:
        ast_if := cast(^Ast_If)ast

        analyze(analyzer, ast_if.condition)
        analyze(analyzer, ast_if.if_true)
        if ast_if.if_false != nil {
            analyze(analyzer, ast_if.if_false)
        }

    case .Return:
        ast_return := cast(^Ast_Return)ast

        // If we aren't in a function, then this is an error.
        in_function := false
        #reverse for info in analyzer.scope_infos {
            if info.is_function_scope {
                in_function = true
                break
            }
        }
        if !in_function {
            report_error(analyzer.file, ast.span, "Return can only be used inside the body of a function.")
        }

        analyze(analyzer, ast_return.expr)

    case .Assign:
        ast_assign := cast(^Ast_Assign)ast

        analyze(analyzer, ast_assign.left)
        // @Temporary. Support more things here.
        assert(ast_assign.left.type == .Var)
        left := cast(^Ast_Var)ast_assign.left

        // If we are assigning to a variable that isn't defined, then that's an error.
        var_is_defined := false
        #reverse for info in analyzer.scope_infos {
            for def in info.defined_variables {
                if def == left.name {
                    var_is_defined = true
                    break
                }
            }
        }
        if !var_is_defined {
            report_error(analyzer.file, ast.span, "Attempt to assign to variable '%v', but it wasn't declared yet.", left.name)
        }

        analyze(analyzer, ast_assign.right)
    }
}

resolve :: proc(analyzer: ^Analyzer, name: string) -> (hops: int, found: bool) {
    #reverse for info in analyzer.scope_infos {
        for def in info.defined_variables {
            if def == name {
                return hops, true
            }
        }

        for def in info.defined_functions {
            if def == name {
                return hops, true
            }
        }

        hops += 1
    }

    return 0, false
}
