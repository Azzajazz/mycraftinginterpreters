package lox

LoxFile :: struct {
    path: string,
    code: string,

    //nocommit: Add token slice here, to be filled in by lexing.
}
