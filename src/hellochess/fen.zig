// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

//!
//! herin lies logic for parsing fen strings into a `Position`
//! and writing a `Position` as a fen string
//! references:
//!  - https://www.chess.com/terms/fen-chess
//!  - https://en.wikipedia.org/wiki/Forsyth%E2%80%93Edwards_Notation
//!

const std = @import("std");

const Position = @import("Position.zig");
const Piece = @import("Piece.zig");
const Coordinate = @import("Coordinate.zig");

const Affiliation = Piece.Affiliation;
const Class = Piece.Class;
const File = Coordinate.File;

pub const starting_position = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

pub const Error = error{
    invalid_character,
    unexpected_space,
    missing_fields,
    unrecognized_side_to_move,
    unrecognized_castling_right,
    invalid_enpassant_file,
    invalid_enpassant_rank,
    invalid_counter,
    piece_count_mismatch,
};

/// parse fen into Position
/// lieniant parsing:
///  - arbitrary number of delimiting spaces
///  - duplicate castling rights ignored
pub fn parse(fen: []const u8) Error!Position {
    var position = Position.initEmpty();

    var fen_index: usize = 0;
    while (fen_index < fen.len and fen[fen_index] == ' ')
        fen_index += 1;
    if (fen_index >= fen.len)
        return Error.missing_fields;

    // -- field 1 : piece placement data
    var square_index: usize = 0;
    while (true) {
        if (fen_index >= fen.len)
            return Error.missing_fields;
        if (square_index >= 64) {
            if (fen[fen_index] == ' ') {
                break;
            } else return Error.piece_count_mismatch;
        }

        const piece = fen[fen_index];
        if (std.ascii.isDigit(piece)) {
            fen_index += 1;
            var count = piece - '0';
            while (count > 0) {
                position.squares[square_index] = Piece.empty();
                count -= 1;
                square_index += 1;
            }
        } else if (std.ascii.isAlphabetic(piece)) {
            const affiliation: Affiliation = if (std.ascii.isUpper(piece))
                .white
            else
                .black;
            const class: Class = switch (std.ascii.toLower(piece)) {
                'p' => .pawn,
                'n' => .knight,
                'b' => .bishop,
                'r' => .rook,
                'q' => .queen,
                'k' => .king,
                else => return Error.invalid_character,
            };
            position.squares[square_index] = Piece.init(class, affiliation);
            const coord = Coordinate.from1d(@intCast(i8, square_index));
            position.pieces[affiliation.index()].set(coord, true);
            switch (class) {
                .king => position.kings[affiliation.index()] = coord,
                else => {},
            }
            fen_index += 1;
            square_index += 1;
        } else if (piece == '/') {
            // assert square_index on file a
            if (@rem(square_index, 8) != 0)
                return Error.piece_count_mismatch;
            fen_index += 1;
        } else return Error.invalid_character;
    }

    while (fen_index < fen.len and fen[fen_index] == ' ')
        fen_index += 1;
    if (fen_index >= fen.len)
        return Error.missing_fields;

    // -- field 2 : side to move
    if (fen[fen_index] == 'w')
        position.side_to_move = .white
    else if (fen[fen_index] == 'b')
        position.side_to_move = .black
    else
        return Error.unrecognized_side_to_move;
    fen_index += 1;

    while (fen_index < fen.len and fen[fen_index] == ' ')
        fen_index += 1;
    if (fen_index >= fen.len)
        return Error.missing_fields;

    // -- field 3 : castling rights
    if (fen[fen_index] == '-')
        fen_index += 1
    else while (fen[fen_index] != ' ') : (fen_index += 1) {
        switch (fen[fen_index]) {
            'K' => position.meta.setCastleKing(.white, true),
            'Q' => position.meta.setCastleQueen(.white, true),
            'k' => position.meta.setCastleKing(.black, true),
            'q' => position.meta.setCastleQueen(.black, true),
            else => return Error.unrecognized_castling_right,
        }
    }

    while (fen_index < fen.len and fen[fen_index] == ' ')
        fen_index += 1;
    if (fen_index >= fen.len)
        return Error.missing_fields;

    // -- field 4 : En Passant target
    if (fen[fen_index] == '-')
        fen_index += 1
    else {
        if (fen_index >= fen.len - 1)
            return Error.missing_fields;
        if (!Coordinate.isFile(fen[fen_index]))
            return Error.invalid_enpassant_file;
        if (!Coordinate.isRank(fen[fen_index + 1]))
            return Error.invalid_enpassant_rank;
        const coord = Coordinate.fromString(fen[fen_index .. fen_index + 2]);
        position.meta.setEnpassantFile(coord.getFile());
        fen_index += 2;
    }

    while (fen_index < fen.len and fen[fen_index] == ' ')
        fen_index += 1;
    if (fen_index >= fen.len)
        return Error.missing_fields;

    // -- field 5 : fifty move counter
    var end: usize = fen_index;
    while (end < fen.len and fen[end] != ' ')
        end += 1;

    const fifty = std.fmt.parseInt(u18, fen[fen_index..end], 10) catch return Error.invalid_counter;
    position.meta.setFiftyCounter(fifty);
    fen_index = end;

    while (fen_index < fen.len and fen[fen_index] == ' ')
        fen_index += 1;
    if (fen_index >= fen.len)
        return Error.missing_fields;

    // -- field 6 : full move counter
    end = fen_index;
    while (end < fen.len and fen[end] != ' ')
        end += 1;

    const fullmove = std.fmt.parseInt(i32, fen[fen_index..end], 10) catch return Error.invalid_counter;
    position.ply = (fullmove - 1) * 2;
    if (position.side_to_move == .black)
        position.ply += 1;

    return position;
}

/// write `position` to `writer` as fen string
pub fn writePosition(writer: anytype, position: Position) void {
    _ = position;
    _ = writer;
    unreachable; // TODO: implement
}

test "fen parse starting_position" {
    const position = try parse(starting_position);

    try std.testing.expectEqual(Affiliation.white, position.side_to_move);
    try std.testing.expectEqual(@as(i32, 0), position.ply);
    try std.testing.expectEqual(true, position.meta.castleKing(.white));
    try std.testing.expectEqual(true, position.meta.castleKing(.black));
    try std.testing.expectEqual(true, position.meta.castleQueen(.white));
    try std.testing.expectEqual(true, position.meta.castleQueen(.black));
    try std.testing.expectEqual(@as(?File, null), position.meta.enpassantFile());
    try std.testing.expectEqual(@as(u18, 0), position.meta.fiftyCounter());

    try std.testing.expectEqual(Piece.init(.king, .white), position.at(Coordinate.e1));
    try std.testing.expectEqual(Piece.init(.king, .black), position.at(Coordinate.e8));
    try std.testing.expectEqual(Piece.init(.queen, .white), position.at(Coordinate.d1));
    try std.testing.expectEqual(Piece.init(.queen, .black), position.at(Coordinate.d8));
    try std.testing.expectEqual(Piece.init(.rook, .white), position.at(Coordinate.a1));
    try std.testing.expectEqual(Piece.init(.rook, .black), position.at(Coordinate.h8));
    try std.testing.expectEqual(Piece.init(.bishop, .white), position.at(Coordinate.f1));
    try std.testing.expectEqual(Piece.init(.bishop, .black), position.at(Coordinate.c8));
    try std.testing.expectEqual(Piece.init(.knight, .white), position.at(Coordinate.b1));
    try std.testing.expectEqual(Piece.init(.knight, .black), position.at(Coordinate.g8));
    try std.testing.expectEqual(Piece.init(.pawn, .white), position.at(Coordinate.b2));
    try std.testing.expectEqual(Piece.init(.pawn, .black), position.at(Coordinate.b7));
    try std.testing.expectEqual(Piece.init(.pawn, .white), position.at(Coordinate.g2));
    try std.testing.expectEqual(Piece.init(.pawn, .black), position.at(Coordinate.g7));

    try verifyBitboards(position);
}

test "fen parse endgame" {
    const fen = "8/5k2/3p4/1p1Pp2p/pP2Pp1P/P4P1K/8/8 b - - 99 50";
    const position = try parse(fen);
    try verifyBitboards(position);
}

/// asserts all bitbards are up to date with squares array
fn verifyBitboards(position: Position) error{ bitboards_out_of_sync, king_out_of_sync }!void {
    var index: usize = 0;
    while (index < 64) : (index += 1) {
        const piece = position.squares[index];
        if (piece.affiliation() == Affiliation.white) {
            if (!position.pieces[0].get(Coordinate.from1d(@intCast(i8, index))))
                return error.bitboards_out_of_sync;
            if (position.pieces[1].get(Coordinate.from1d(@intCast(i8, index))))
                return error.bitboards_out_of_sync;
        } else if (piece.affiliation() == Affiliation.black) {
            if (position.pieces[0].get(Coordinate.from1d(@intCast(i8, index))))
                return error.bitboards_out_of_sync;
            if (!position.pieces[1].get(Coordinate.from1d(@intCast(i8, index))))
                return error.bitboards_out_of_sync;
        } else {
            if (position.pieces[0].get(Coordinate.from1d(@intCast(i8, index))))
                return error.bitboards_out_of_sync;
            if (position.pieces[1].get(Coordinate.from1d(@intCast(i8, index))))
                return error.bitboards_out_of_sync;
        }

        if (piece.class() == Class.king) {
            if (position.kings[piece.affiliation().?.index()].index() != index)
                return error.king_out_of_sync;
        }
    }
}