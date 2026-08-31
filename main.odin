package lox

import "core:flags"
import "core:os"
import "core:fmt"
import "core:reflect"
import "core:strings"
import "core:strconv"

Token_Type :: enum {
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    Semicolon,
    Comma,
    Plus,
    Minus,
    Star,
    BangEqual,
    EqualEqual,
    LessEqual,
    GreaterEqual,
    Less,
    Greater,
    Slash,
    Dot,
    Eof,

    Identifier,
    And, 
    Class, 
    Else, 
    False, 
    For, 
    Fun, 
    If, 
    Nil, 
    Or, 
    Return, 
    Super, 
    This, 
    True, 
    Var, 
    While,

    Number,
    String,
}

Token :: struct {
    type: Token_Type,
    code: string,

    value: struct #raw_union {
        number: f32,
        str: string,
    }
}

Lexer :: struct {
    code: string,
    code_index: int,
}

report_parse_error :: proc(format: string, args: ..any) {
    fmt.eprint("Error: ")
    fmt.eprintfln(format, ..args)
    os.exit(1)
}

report_internal_error :: proc(format: string, args: ..any) {
    fmt.eprint("Internal error: ")
    fmt.eprintfln(format, ..args)
    os.exit(1)
}

lex_token :: proc(lexer: ^Lexer) -> Token {
    token: Token

    for lexer.code_index < len(lexer.code) && (strings.is_ascii_space(cast(rune)lexer.code[lexer.code_index]) || strings.starts_with(lexer.code[lexer.code_index:], "//")){
        for lexer.code_index < len(lexer.code) && strings.is_ascii_space(cast(rune)lexer.code[lexer.code_index]) {
            lexer.code_index += 1
        }

        // Skip inline comments
        if strings.starts_with(lexer.code[lexer.code_index:], "//") {
            newline_index := strings.index_byte(lexer.code[lexer.code_index:], '\n')
            if newline_index == -1 {
                lexer.code_index = len(lexer.code)
            } else {
                lexer.code_index += newline_index
            }
        }
    }

    if lexer.code_index >= len(lexer.code) {
        token.type = .Eof
    } else {
        c := lexer.code[lexer.code_index]
        switch c {
        case '(':
            token.type = .LeftParen
            token.code = "("
            lexer.code_index += 1
        case ')':
            token.type = .RightParen
            token.code = ")"
            lexer.code_index += 1
        case '{':
            token.type = .LeftBrace
            token.code = "{"
            lexer.code_index += 1
        case '}':
            token.type = .RightBrace
            token.code = "}"
            lexer.code_index += 1
        case ';':
            token.type = .Semicolon
            token.code = ";"
            lexer.code_index += 1
        case ',':
            token.type = .Comma
            token.code = ""
            lexer.code_index += 1
        case '+':
            token.type = .Plus
            token.code = "+"
            lexer.code_index += 1
        case '-':
            token.type = .Minus
            token.code = "-"
            lexer.code_index += 1
        case '*':
            token.type = .Star
            token.code = "*"
            lexer.code_index += 1
        case '!':
            if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index + 1] == '=' {
                token.type = .BangEqual
                token.code = "!="
                lexer.code_index += 2
            } else {
                report_internal_error("TODO: Bang for booleans")
            }
        case '=':
            if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index + 1] == '=' {
                token.type = .EqualEqual
                token.code = "=="
                lexer.code_index += 2
            } else {
                report_internal_error("TODO: '=' for assignment")
            }
        case '<':
            if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index + 1] == '=' {
                token.type = .LessEqual
                token.code = "<="
                lexer.code_index += 2
            } else {
                token.type = .Less
                token.code = "<"
                lexer.code_index += 1
            }
        case '>':
            if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index + 1] == '=' {
                token.type = .GreaterEqual
                token.code = ">="
                lexer.code_index += 2
            } else {
                token.type = .Greater
                token.code = ">"
                lexer.code_index += 1
            }
        case '/':
            token.type = .Slash
            token.code = "/"
            lexer.code_index += 1
        case '.':
            token.type = .Dot
            token.code = "."
            lexer.code_index += 1
        }

        // If we get here, then this is a string literal, a number, an identifier or a keyword.
        if c == '"' {
            string_start_index := lexer.code_index
            lexer.code_index += 1
            for lexer.code_index < len(lexer.code) && lexer.code[lexer.code_index] != '"' {
                if lexer.code[lexer.code_index] == '\n' {
                    report_parse_error("Strings must be terminated on the same line they start on.")
                }
                lexer.code_index += 1
            }

            if lexer.code_index >= len(lexer.code) {
                report_parse_error("Expected a string to be terminated, but it wasn't.")
            }

            assert(lexer.code[lexer.code_index] == '"')
            lexer.code_index += 1

            assert(string_start_index <= lexer.code_index - 2)
            token.type = .String
            token.code = lexer.code[string_start_index:lexer.code_index]
            token.value.str = lexer.code[string_start_index + 1:lexer.code_index - 1]
        } else if '0' <= c && c <= '9' {
            number_start_index := lexer.code_index

            for lexer.code_index < len(lexer.code) && ('0' <= lexer.code[lexer.code_index] && lexer.code[lexer.code_index] <= '9') {
                lexer.code_index += 1
            }

            if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index] == '.' && ('0' <= lexer.code[lexer.code_index + 1] && lexer.code[lexer.code_index + 1] <= '9') {
                lexer.code_index += 2

                for lexer.code_index < len(lexer.code) && ('0' <= lexer.code[lexer.code_index] && lexer.code[lexer.code_index] <= '9') {
                    lexer.code_index += 1
                }
            }

            code_repr := lexer.code[number_start_index:lexer.code_index]

            token.type = .Number
            token.code = code_repr
            parse_ok: bool
            token.value.number, parse_ok = strconv.parse_f32(code_repr)
            assert(parse_ok)
        } else if ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || c == '_' {
            lex_identifier_or_keyword(lexer, &token)
        } else {
            report_parse_error("Unexpected character '%v'.", cast(rune)c)
        }
    }

    return token
}

lex_identifier_or_keyword :: proc(lexer: ^Lexer, token: ^Token) {
    // This is an identifier.
    identifier_start_index := lexer.code_index
    c1 := lexer.code[lexer.code_index]
    for ('a' <= c1 && c1 <= 'z') || ('A' <= c1 && c1 <= 'Z') || c1 == '_' || ('0' <= c1 && c1 <= '9') {
        lexer.code_index += 1
        if lexer.code_index >= len(lexer.code) do break
        c1 = lexer.code[lexer.code_index]
    }

    identifier := lexer.code[identifier_start_index:lexer.code_index]

    switch {
    case identifier == "and": 
        token.type = .And
        token.code = "and"
    case identifier == "class": 
        token.type = .Class
        token.code = "class"
    case identifier == "else": 
        token.type = .Else
        token.code = "else"
    case identifier == "false": 
        token.type = .False
        token.code = "false"
    case identifier == "for": 
        token.type = .For
        token.code = "for"
    case identifier == "fun": 
        token.type = .Fun
        token.code = "fun"
    case identifier == "if": 
        token.type = .If
        token.code = "if"
    case identifier == "nil": 
        token.type = .Nil
        token.code = "nil"
    case identifier == "or": 
        token.type = .Or
        token.code = "or"
    case identifier == "return": 
        token.type = .Return
        token.code = "return"
    case identifier == "super": 
        token.type = .Super
        token.code = "super"
    case identifier == "this": 
        token.type = .This
        token.code = "this"
    case identifier == "true": 
        token.type = .True
        token.code = "true"
    case identifier == "var": 
        token.type = .Var
        token.code = "var"
    case identifier == "while":
        token.type = .While
        token.code = "while"
    case:
        token.type = .Identifier
        token.code = identifier
    }
}

dump_token :: proc(token: Token) {
    type_str, type_str_ok := reflect.enum_name_from_value(token.type)
    assert(type_str_ok)
    fmt.print(type_str)
    fmt.printf(" %v", token.code)
    if token.type == .Number {
        fmt.printfln(" %v", token.value.number)
    } else if token.type == .String {
        fmt.printfln(" %v", token.value.str)
    } else {
        fmt.println(" null")
    }
}

Options :: struct {
    source_file: string `args:"pos=0,required" usage:"The source file to interpret."`,
    lex_only: bool `usage:"Only lex the input."`,
}
options: Options

main :: proc() {
    flags.parse_or_exit(&options, os.args)

    source_file_data, source_file_data_err := os.read_entire_file(options.source_file, context.allocator)
    defer delete(source_file_data)
    if source_file_data_err != nil {
        fmt.eprintfln("ERROR: Could not open source file %v.", options.source_file)
        os.exit(1)
    }

    if options.lex_only {
        lexer := Lexer{code = cast(string)source_file_data, code_index = 0}
        token: Token
        for token.type != .Eof {
            token = lex_token(&lexer)
            //dump_token(token)
        }
    }
}
