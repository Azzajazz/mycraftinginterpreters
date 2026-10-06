package lox

import "core:fmt"

Scope_Info :: struct {
    // @Performance: Maybe a set here?
    defined_variables: [dynamic]string,
    defined_functions: [dynamic]string,
}

delete_scope_info :: proc(info: Scope_Info) {
    delete(info.defined_variables)
    delete(info.defined_functions)
}

Analyzer :: struct {
    file: ^Lox_File,
    scope_infos: [dynamic]Scope_Info,
}

delete_analyzer :: proc(analyzer: ^Analyzer) {
    for info in analyzer.scope_infos {
        delete_scope_info(info)
    }

    delete(analyzer.scope_infos)
}

add_scope_info :: proc(analyzer: ^Analyzer) {
    resize(&analyzer.scope_infos, len(analyzer.scope_infos) + 1)
}

remove_scope_info :: proc(analyzer: ^Analyzer) {
    scope_info := pop(&analyzer.scope_infos)
    delete_scope_info(scope_info)
}

add_function_definition :: proc(analyzer: ^Analyzer, name: string) {
    info := &analyzer.scope_infos[len(analyzer.scope_infos) - 1]
    append(&info.defined_functions, name)
}

add_variable_definition :: proc(analyzer: ^Analyzer, name: string) {
    info := &analyzer.scope_infos[len(analyzer.scope_infos) - 1]
    append(&info.defined_variables, name)
}

analyze :: proc(analyzer: ^Analyzer, ast: ^Ast) {
    switch ast.type {
    case .Scope:
        ast_scope := cast(^Ast_Scope)ast

        add_scope_info(analyzer)
        defer remove_scope_info(analyzer)

        for child in ast_scope.children {
            analyze(analyzer, child)
        }

    case .Function:
        ast_function := cast(^Ast_Function)ast

        add_function_definition(analyzer, ast_function.name)

        add_scope_info(analyzer)
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

        add_variable_definition(analyzer, ast_vardef.name)

    case .Print:
        ast_print := cast(^Ast_Print)ast

        analyze(analyzer, ast_print.expr)

    case .Var:
        ast_var := cast(^Ast_Var)ast

        hops, found := resolve(analyzer, ast_var.name)
        if !found {
            report_error(analyzer.file, ast.span, "Variable %v was used, but it hasn't been defined yet.", ast_var.name)
        }

        ast_var.hops_to_resolve = hops

    case .Call:
        ast_call := cast(^Ast_Call)ast

        analyze(analyzer, ast_call.identifier_expr)
        for arg in ast_call.args {
            analyze(analyzer, arg)
        }

    case .Negate:
        ast_negate := cast(^Ast_Negate)ast

        analyze(analyzer, ast_negate.operand)

    case .Plus: fallthrough
    case .Minus: fallthrough
    case .Times: fallthrough
    case .Divide: fallthrough
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

        analyze(analyzer, ast_return.expr)

    case .Assign:
        ast_assign := cast(^Ast_Assign)ast

        analyze(analyzer, ast_assign.value)
    }
}

resolve :: proc(analyzer: ^Analyzer, name: string) -> (hops: int, found: bool) {
    #reverse for info in analyzer.scope_infos {
        defer hops += 1

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
    }

    return 0, false
}
