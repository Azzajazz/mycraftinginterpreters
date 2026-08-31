package lox

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
    line_start: int,
    char_start: int,
    // @Compactness: Maybe these are superfluous?
    line_end: int,
    char_end: int,

    type: Token_Type,
    code: string,

    value: struct #raw_union {
        number: f32,
        str: string,
    }
}

Lexer :: struct {
    file_name: string,
    line: int,
    char: int,
    code: string,
    code_index: int,
}

report_lex_error :: proc(lexer: ^Lexer, token: Token, format: string, args: ..any) {
    fmt.eprintf("%v(%v:%v) Error: ", lexer.file_name, token.line_start + 1, token.char_start + 1)
    fmt.eprintfln(format, ..args)
    os.exit(1)
}

advance_lexer :: proc(lexer: ^Lexer, steps: int) {
    for _ in 0..<steps {
        if lexer.code_index >= len(lexer.code) do break

        c := lexer.code[lexer.code_index]
        lexer.code_index += 1

        if c == '\n' {
            lexer.line += 1
            lexer.char = 0
        } else {
            lexer.char += 1
        }
    }
}

lex_token :: proc(lexer: ^Lexer) -> Token {
    token: Token

    for lexer.code_index < len(lexer.code) && (strings.is_ascii_space(cast(rune)lexer.code[lexer.code_index]) || strings.starts_with(lexer.code[lexer.code_index:], "//")){
        for lexer.code_index < len(lexer.code) && strings.is_ascii_space(cast(rune)lexer.code[lexer.code_index]) {
            advance_lexer(lexer, 1)
        }

        // Skip inline comments
        if strings.starts_with(lexer.code[lexer.code_index:], "//") {
            newline_index := strings.index_byte(lexer.code[lexer.code_index:], '\n')
            if newline_index == -1 {
                lexer.code_index = len(lexer.code)
                // Note we don't have to update lexer.line and lexer.char here, since we're at the end of input.
            } else {
                advance_lexer(lexer, newline_index)
            }
        }
    }

    token.line_start = lexer.line
    token.char_start = lexer.char

    if lexer.code_index >= len(lexer.code) {
        token.type = .Eof
    } else {
        c := lexer.code[lexer.code_index]

        // If we get here, then this is a string literal, a number, an identifier or a keyword.
        if c == '"' {
            // @Robustness: We should probaly copy the string out of the code here.
            string_start_index := lexer.code_index
            advance_lexer(lexer, 1)
            for lexer.code_index < len(lexer.code) && lexer.code[lexer.code_index] != '"' {
                if lexer.code[lexer.code_index] == '\n' {
                    report_lex_error(lexer, token, "Strings must be terminated on the same line they start on.")
                }
                advance_lexer(lexer, 1)
            }

            if lexer.code_index >= len(lexer.code) {
                report_lex_error(lexer, token, "Expected a string to be terminated, but it wasn't.")
            }

            assert(lexer.code[lexer.code_index] == '"')
            advance_lexer(lexer, 1)

            assert(string_start_index <= lexer.code_index - 2)
            token.type = .String
            token.code = lexer.code[string_start_index:lexer.code_index]
            token.value.str = lexer.code[string_start_index + 1:lexer.code_index - 1]
        } else if '0' <= c && c <= '9' {
            number_start_index := lexer.code_index

            for lexer.code_index < len(lexer.code) && ('0' <= lexer.code[lexer.code_index] && lexer.code[lexer.code_index] <= '9') {
                advance_lexer(lexer, 1)
            }

            if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index] == '.' && ('0' <= lexer.code[lexer.code_index + 1] && lexer.code[lexer.code_index + 1] <= '9') {
                advance_lexer(lexer, 2)

                for lexer.code_index < len(lexer.code) && ('0' <= lexer.code[lexer.code_index] && lexer.code[lexer.code_index] <= '9') {
                    advance_lexer(lexer, 1)
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
            switch c {
            case '(':
                token.type = .LeftParen
                token.code = "("
                advance_lexer(lexer, 1)
            case ')':
                token.type = .RightParen
                token.code = ")"
                advance_lexer(lexer, 1)
            case '{':
                token.type = .LeftBrace
                token.code = "{"
                advance_lexer(lexer, 1)
            case '}':
                token.type = .RightBrace
                token.code = "}"
                advance_lexer(lexer, 1)
            case ';':
                token.type = .Semicolon
                token.code = ";"
                advance_lexer(lexer, 1)
            case ',':
                token.type = .Comma
                token.code = ""
                advance_lexer(lexer, 1)
            case '+':
                token.type = .Plus
                token.code = "+"
                advance_lexer(lexer, 1)
            case '-':
                token.type = .Minus
                token.code = "-"
                advance_lexer(lexer, 1)
            case '*':
                token.type = .Star
                token.code = "*"
                advance_lexer(lexer, 1)
            case '!':
                if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index + 1] == '=' {
                    token.type = .BangEqual
                    token.code = "!="
                    advance_lexer(lexer, 2)
                } else {
                    report_internal_error("TODO: Bang for booleans")
                }
            case '=':
                if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index + 1] == '=' {
                    token.type = .EqualEqual
                    token.code = "=="
                    advance_lexer(lexer, 2)
                } else {
                    report_internal_error("TODO: '=' for assignment")
                }
            case '<':
                if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index + 1] == '=' {
                    token.type = .LessEqual
                    token.code = "<="
                    advance_lexer(lexer, 2)
                } else {
                    token.type = .Less
                    token.code = "<"
                    advance_lexer(lexer, 1)
                }
            case '>':
                if lexer.code_index < len(lexer.code) - 1 && lexer.code[lexer.code_index + 1] == '=' {
                    token.type = .GreaterEqual
                    token.code = ">="
                    advance_lexer(lexer, 2)
                } else {
                    token.type = .Greater
                    token.code = ">"
                    advance_lexer(lexer, 1)
                }
            case '/':
                token.type = .Slash
                token.code = "/"
                advance_lexer(lexer, 1)
            case '.':
                token.type = .Dot
                token.code = "."
                advance_lexer(lexer, 1)
            case:
                report_lex_error(lexer, token, "Unexpected character '%v'.", cast(rune)c)
            }
        }
    }

    token.line_end = lexer.line
    token.char_end = lexer.char

    return token
}

lex_identifier_or_keyword :: proc(lexer: ^Lexer, token: ^Token) {
    // This is an identifier.
    identifier_start_index := lexer.code_index
    c1 := lexer.code[lexer.code_index]
    for ('a' <= c1 && c1 <= 'z') || ('A' <= c1 && c1 <= 'Z') || c1 == '_' || ('0' <= c1 && c1 <= '9') {
        advance_lexer(lexer, 1)
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

