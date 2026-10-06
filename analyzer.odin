package lox

import "core:fmt"

Scope_Info :: struct {
    variable_declarations: map[string]^Ast_Var_Definition,
    function_declarations: map[string]^Ast_Function,
}

delete_scope_info :: proc(info: Scope_Info) {
    delete(info.variable_declarations)
    delete(info.function_declarations)
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

get_current_scope_info :: proc(analyzer: ^Analyzer) -> ^Scope_Info {
    return &analyzer.scope_infos[len(analyzer.scope_infos) - 1]
}

analyze :: proc(analyzer: ^Analyzer, ast: ^Ast) {
    // @TODO: Remove #partial probably.
    #partial switch ast.type {
    case .Scope:
        ast_scope := cast(^Ast_Scope)ast

        add_scope_info(analyzer)
        defer remove_scope_info(analyzer)

        for child in ast_scope.children {
            analyze(analyzer, child)
        }

    case .Function:
        ast_function := cast(^Ast_Function)ast

        scope_info := get_current_scope_info(analyzer)
        scope_info.function_declarations[ast_function.name] = ast_function

        add_scope_info(analyzer)
        defer remove_scope_info(analyzer)

        // Treat function parameters as declarations.
        scope_info = get_current_scope_info(analyzer)

        for child in ast_function.body.children {
            analyze(analyzer, child)
        }

    case .VarDefinition:
        ast_vardef := cast(^Ast_Var_Definition)ast

        scope_info := get_current_scope_info(analyzer)
        scope_info.variable_declarations[ast_vardef.name] = ast_vardef

    case .Print:
        ast_print := cast(^Ast_Print)ast

        analyze(analyzer, ast_print.expr)

    case .Var:
        ast_var := cast(^Ast_Var)ast

        decl, found := resolve(analyzer, ast_var.name)
        if !found {
            fmt.println(analyzer)
            report_error(analyzer.file, ast.span, "Variable %v was used, but it hasn't been declared yet.", ast_var.name)
        }

        ast_var.resolved_declaration = decl

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

    case:
        fmt.panicf("TODO: %v", ast.type)
    }
}

resolve :: proc(analyzer: ^Analyzer, name: string) -> (decl: ^Ast, found: bool) {
    #reverse for info in analyzer.scope_infos {
        decl, found = info.variable_declarations[name]
        if found do return decl, found

        decl, found = info.function_declarations[name]
        if found do return decl, found
    }

    return nil, false
}
