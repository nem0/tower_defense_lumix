-- Basic Chess Implementation for LumixEngine
-- This script sets up a chess board and pieces, handles mouse input for moves,
-- and validates basic chess rules.

local lmath = require "chess/math"

local BOARD_SIZE = 8
local SQUARE_SIZE = 7.2 / 8  -- Size of each square
local PIECE_HEIGHT = 0.02  -- Height offset for pieces above board (FBX pivots are usually at the base)

-- Rotate all models by +90 degrees around X.
-- Quaternion is {x, y, z, w}.
local MODEL_ROT_X90 = {0.7071067811865476, 0, 0, -0.7071067811865476}

-- Chess set assets (FBX is imported with `split = true`, so individual meshes are addressed as:
--   <MeshName>.fbx:<SourceFBX>
local CHESS_SET_FBX = "chess/Chess_Set/Chess_Set.fbx"
local MAT_PIECES_WHITE = "chess/Chess_Set/pieces.mat"
local MAT_PIECES_BLACK = "chess/Chess_Set/pieces_black.mat"
local MAT_BOARD = "chess/Chess_Set/board.mat"

local BOARD_MODEL = "Board_low.fbx:" .. CHESS_SET_FBX
local CHESS_MODEL_SCALE = 0.3
local PIECE_Y_OFFSET = 1  -- Configurable Y offset for all pieces

-- Piece types
local PIECE_TYPES = {
    PAWN = 1,
    ROOK = 2,
    KNIGHT = 3,
    BISHOP = 4,
    QUEEN = 5,
    KING = 6
}

-- Colors
local WHITE = 1
local BLACK = 2

-- Board state: 8x8 grid, each cell can hold a piece or nil
local board = {}
local pieces = {}  -- List of piece entities
local selected_piece = nil
local current_turn = WHITE
local camera_entity = nil
local mouse_pos = {0.5, 0.5}  -- Normalized mouse position
local hovered_piece = nil
local hover_time = 0
local dragging = false
local dragged_piece = nil
local dropping = false
local undo_stack = {}
local undoMove
local restartGame

local gui_module = nil
local canvas = nil
local turn_text = nil
local undo_button = nil
local restart_button = nil

local HOVER_LIFT = 0.1
local HOVER_BOB_AMPLITUDE = 0.05
local HOVER_BOB_SPEED = 6
local HOVER_SMOOTH = 12
local DRAG_LIFT = 0.2
local SNAP_LERP_SPEED = 10

-- AI settings
local AI_ENABLED = true
local AI_PLAYER = BLACK  -- AI plays as black
local AI_THINK_TIME = 1.0  -- Seconds to wait before AI makes a move
local AI_MAX_DEPTH = 3
local ai_timer = 0
local ai_thinking = false
local game_over = false

local function updateTurnText()
    if not turn_text or not turn_text.gui_text then
        return
    end
    turn_text.gui_text.text = (current_turn == WHITE and "White's turn" or "Black's turn")
    if current_turn ~= AI_PLAYER and isKingInCheck(current_turn) then
        turn_text.gui_text.text = turn_text.gui_text.text .. " (Check!)"
    end
end

local function squareToBasePos(x, z)
    local pos_x = (x - 1) * SQUARE_SIZE - (BOARD_SIZE / 2 - 0.5) * SQUARE_SIZE
    local pos_z = (z - 1) * SQUARE_SIZE - (BOARD_SIZE / 2 - 0.5) * SQUARE_SIZE
    return {pos_x, PIECE_HEIGHT + PIECE_Y_OFFSET, pos_z}
end

local function isAnyPieceAnimating()
    for _, piece in ipairs(pieces) do
        if piece.animating then
            return true
        end
    end
    return false
end

local function chessModel(mesh_name)
    return mesh_name .. ".fbx:" .. CHESS_SET_FBX
end

-- AI Functions
local withTemporaryMove

function getAllValidMoves(color)
    local moves = {}
    for _, piece in ipairs(pieces) do
        if piece.color == color then
            for x = 1, BOARD_SIZE do
                for z = 1, BOARD_SIZE do
                    if isLegalMove(piece, piece.x, piece.z, x, z) then
                        table.insert(moves, {piece = piece, from_x = piece.x, from_z = piece.z, to_x = x, to_z = z})
                    end
                end
            end
        end
    end
    return moves
end

local function pieceValue(piece_type)
    if piece_type == PIECE_TYPES.PAWN then return 100 end
    if piece_type == PIECE_TYPES.KNIGHT then return 320 end
    if piece_type == PIECE_TYPES.BISHOP then return 330 end
    if piece_type == PIECE_TYPES.ROOK then return 500 end
    if piece_type == PIECE_TYPES.QUEEN then return 900 end
    if piece_type == PIECE_TYPES.KING then return 20000 end
    return 0
end

local PST = {
    PAWN = {
        { 0,  0,  0,  0,  0,  0,  0,  0},
        { 5, 10, 10,-20,-20, 10, 10,  5},
        { 5, -5,-10,  0,  0,-10, -5,  5},
        { 0,  0,  0, 20, 20,  0,  0,  0},
        { 5,  5, 10, 25, 25, 10,  5,  5},
        {10, 10, 20, 30, 30, 20, 10, 10},
        {50, 50, 50, 50, 50, 50, 50, 50},
        { 0,  0,  0,  0,  0,  0,  0,  0}
    },
    KNIGHT = {
        {-50,-40,-30,-30,-30,-30,-40,-50},
        {-40,-20,  0,  0,  0,  0,-20,-40},
        {-30,  0, 10, 15, 15, 10,  0,-30},
        {-30,  5, 15, 20, 20, 15,  5,-30},
        {-30,  0, 15, 20, 20, 15,  0,-30},
        {-30,  5, 10, 15, 15, 10,  5,-30},
        {-40,-20,  0,  5,  5,  0,-20,-40},
        {-50,-40,-30,-30,-30,-30,-40,-50}
    },
    BISHOP = {
        {-20,-10,-10,-10,-10,-10,-10,-20},
        {-10,  0,  0,  0,  0,  0,  0,-10},
        {-10,  0,  5, 10, 10,  5,  0,-10},
        {-10,  5,  5, 10, 10,  5,  5,-10},
        {-10,  0, 10, 10, 10, 10,  0,-10},
        {-10, 10, 10, 10, 10, 10, 10,-10},
        {-10,  5,  0,  0,  0,  0,  5,-10},
        {-20,-10,-10,-10,-10,-10,-10,-20}
    },
    ROOK = {
        { 0,  0,  0,  5,  5,  0,  0,  0},
        {-5,  0,  0,  0,  0,  0,  0, -5},
        {-5,  0,  0,  0,  0,  0,  0, -5},
        {-5,  0,  0,  0,  0,  0,  0, -5},
        {-5,  0,  0,  0,  0,  0,  0, -5},
        {-5,  0,  0,  0,  0,  0,  0, -5},
        { 5, 10, 10, 10, 10, 10, 10,  5},
        { 0,  0,  0,  0,  0,  0,  0,  0}
    },
    QUEEN = {
        {-20,-10,-10, -5, -5,-10,-10,-20},
        {-10,  0,  0,  0,  0,  0,  0,-10},
        {-10,  0,  5,  5,  5,  5,  0,-10},
        { -5,  0,  5,  5,  5,  5,  0, -5},
        {  0,  0,  5,  5,  5,  5,  0, -5},
        {-10,  5,  5,  5,  5,  5,  0,-10},
        {-10,  0,  5,  0,  0,  0,  0,-10},
        {-20,-10,-10, -5, -5,-10,-10,-20}
    },
    KING = {
        {-30,-40,-40,-50,-50,-40,-40,-30},
        {-30,-40,-40,-50,-50,-40,-40,-30},
        {-30,-40,-40,-50,-50,-40,-40,-30},
        {-30,-40,-40,-50,-50,-40,-40,-30},
        {-20,-30,-30,-40,-40,-30,-30,-20},
        {-10,-20,-20,-20,-20,-20,-20,-10},
        { 20, 20,  0,  0,  0,  0, 20, 20},
        { 20, 30, 10,  0,  0, 10, 30, 20}
    }
}

local function pieceSquareValue(piece, x, z)
    local table_ref = nil
    if piece.type == PIECE_TYPES.PAWN then table_ref = PST.PAWN end
    if piece.type == PIECE_TYPES.KNIGHT then table_ref = PST.KNIGHT end
    if piece.type == PIECE_TYPES.BISHOP then table_ref = PST.BISHOP end
    if piece.type == PIECE_TYPES.ROOK then table_ref = PST.ROOK end
    if piece.type == PIECE_TYPES.QUEEN then table_ref = PST.QUEEN end
    if piece.type == PIECE_TYPES.KING then table_ref = PST.KING end
    if not table_ref then return 0 end

    local row = (piece.color == WHITE) and z or (9 - z)
    return table_ref[row][x] or 0
end

local function evaluatePosition(color)
    local score = 0

    for _, piece in ipairs(pieces) do
        local value = pieceValue(piece.type) + pieceSquareValue(piece, piece.x, piece.z)
        if piece.color == color then
            score = score + value
        else
            score = score - value
        end
    end

    local opp_color = (color == WHITE) and BLACK or WHITE

    if isKingInCheck(color) then
        score = score - 200
    end

    if isKingInCheck(opp_color) then
        score = score + 200
    end

    return score
end

local evaluateMove

evaluateMove = function(move)
    local score = 0

    -- Prefer captures
    if board[move.to_x][move.to_z] then
        local captured_type = board[move.to_x][move.to_z].type
        score = score + pieceValue(captured_type)
    end

    -- Prefer center control
    local center_distance = math.abs(move.to_x - 4.5) + math.abs(move.to_z - 4.5)
    score = score + (8 - center_distance) * 3

    -- Prefer advancing pawns
    if move.piece.type == PIECE_TYPES.PAWN then
        local direction = (move.piece.color == WHITE) and 1 or -1
        score = score + (move.to_z - move.from_z) * direction * 4
    end

    return score
end

local function scoreMoveForOrder(move)
    local score = evaluateMove(move)
    local captured = board[move.to_x][move.to_z]
    if captured then
        score = score + pieceValue(captured.type) * 10
    end
    return score
end

local function orderMoves(moves)
    table.sort(moves, function(a, b)
        return scoreMoveForOrder(a) > scoreMoveForOrder(b)
    end)
end

local function minimax(color, depth, alpha, beta, maximizing)
    if depth == 0 then
        return evaluatePosition(color)
    end

    local side_color = maximizing and color or ((color == WHITE) and BLACK or WHITE)
    local moves = getAllValidMoves(side_color)
    if #moves == 0 then
        if isKingInCheck(side_color) then
            return maximizing and -100000 or 100000
        end
        return 0
    end

    orderMoves(moves)

    local best = maximizing and -math.huge or math.huge
    for _, move in ipairs(moves) do
        local score = withTemporaryMove(move.piece, move.from_x, move.from_z, move.to_x, move.to_z, function()
            return minimax(color, depth - 1, alpha, beta, not maximizing)
        end)

        if maximizing then
            if score > best then best = score end
            if best > alpha then alpha = best end
            if beta <= alpha then
                break
            end
        else
            if score < best then best = score end
            if best < beta then beta = best end
            if beta <= alpha then
                break
            end
        end
    end

    return best
end

function makeAIMove()
    if not AI_ENABLED or current_turn ~= AI_PLAYER or game_over then return end
    
    local moves = getAllValidMoves(AI_PLAYER)
    if #moves == 0 then return end  -- No valid moves
    
    -- If king is in check, only consider moves that get out of check
    if isKingInCheck(AI_PLAYER) then
        local check_escape_moves = {}
        for _, move in ipairs(moves) do
            if not wouldMoveLeaveKingInCheck(move.piece, move.from_x, move.from_z, move.to_x, move.to_z) then
                table.insert(check_escape_moves, move)
            end
        end
        moves = check_escape_moves
        if #moves == 0 then return end  -- No way to escape check
    end
    
    -- Evaluate all moves and pick the best one
    local best_move = nil
    local best_score = -math.huge

    for _, move in ipairs(moves) do
        local score = withTemporaryMove(move.piece, move.from_x, move.from_z, move.to_x, move.to_z, function()
            return minimax(AI_PLAYER, AI_MAX_DEPTH - 1, -math.huge, math.huge, false)
        end)
        score = score + evaluateMove(move) * 0.25
        if score > best_score then
            best_score = score
            best_move = move
        end
    end
    
    if best_move then
        movePiece(best_move.piece, best_move.to_x, best_move.to_z)
        LumixAPI.logInfo("AI moved " .. best_move.piece.type .. " from " .. best_move.from_x .. "," .. best_move.from_z .. " to " .. best_move.to_x .. "," .. best_move.to_z)
    end
end

-- Check detection functions
local function isSquareAttackedByPiece(piece, from_x, from_z, to_x, to_z)
    local dx = to_x - from_x
    local dz = to_z - from_z

    if piece.type == PIECE_TYPES.PAWN then
        local direction = (piece.color == WHITE) and 1 or -1
        return dz == direction and math.abs(dx) == 1
    elseif piece.type == PIECE_TYPES.ROOK then
        return (dx == 0 or dz == 0) and isPathClear(from_x, from_z, to_x, to_z)
    elseif piece.type == PIECE_TYPES.KNIGHT then
        return (math.abs(dx) == 2 and math.abs(dz) == 1) or (math.abs(dx) == 1 and math.abs(dz) == 2)
    elseif piece.type == PIECE_TYPES.BISHOP then
        return math.abs(dx) == math.abs(dz) and isPathClear(from_x, from_z, to_x, to_z)
    elseif piece.type == PIECE_TYPES.QUEEN then
        return ((dx == 0 or dz == 0) or math.abs(dx) == math.abs(dz)) and isPathClear(from_x, from_z, to_x, to_z)
    elseif piece.type == PIECE_TYPES.KING then
        return math.abs(dx) <= 1 and math.abs(dz) <= 1
    end

    return false
end

function isSquareAttacked(x, z, by_color)
    -- Check if a square is attacked by any piece of the given color
    for _, piece in ipairs(pieces) do
        if piece.color == by_color and isSquareAttackedByPiece(piece, piece.x, piece.z, x, z) then
            return true
        end
    end
    return false
end

function isKingInCheck(color)
    -- Find the king
    local king = nil
    for _, piece in ipairs(pieces) do
        if piece.type == PIECE_TYPES.KING and piece.color == color then
            king = piece
            break
        end
    end
    if not king then return false end
    
    -- Check if any enemy piece can attack the king's square
    local enemy_color = (color == WHITE) and BLACK or WHITE
    return isSquareAttacked(king.x, king.z, enemy_color)
end

function hasLegalMoves(color)
    local moves = getAllValidMoves(color)
    return #moves > 0
end

function isCheckmate(color)
    return isKingInCheck(color) and not hasLegalMoves(color)
end

function isStalemate(color)
    return not isKingInCheck(color) and not hasLegalMoves(color)
end

function checkGameOver()
    if isCheckmate(WHITE) then
        turn_text.gui_text.text = "Checkmate! Black wins!"
        LumixAPI.logInfo("Game Over: Checkmate - Black wins")
        return true
    elseif isCheckmate(BLACK) then
        turn_text.gui_text.text = "Checkmate! White wins!"
        LumixAPI.logInfo("Game Over: Checkmate - White wins")
        return true
    elseif isStalemate(current_turn) then
        turn_text.gui_text.text = "Stalemate! Draw!"
        LumixAPI.logInfo("Game Over: Stalemate - Draw")
        return true
    end
    return false
end

function start()
    -- Initialize board state
    for i = 1, BOARD_SIZE do
        board[i] = {}
        for j = 1, BOARD_SIZE do
            board[i][j] = nil
        end
    end

    -- Find or create camera entity
    camera_entity = this.world:createEntityEx{
        name = "camera",
        position = {0, 10, 7},
        rotation = {0, 0, 0, 1},
        camera = {}
    }

    -- Look at the board center so picking stays aligned.
    do
        local target = {0, 0, 0}
        local pos = camera_entity.position
        local dir = {
            target[1] - pos[1],
            target[2] - pos[2],
            target[3] - pos[3]
        }
        local horiz = math.sqrt(dir[1] * dir[1] + dir[3] * dir[3])
        local yaw = math.atan2(dir[1], dir[3]) + math.pi
        local pitch = -math.atan2(dir[2], horiz)
        local yaw_rot = lmath.makeQuatFromYaw(yaw)
        local pitch_rot = lmath.makeQuatFromPitch(pitch)
        camera_entity.rotation = lmath.mulQuat(yaw_rot, pitch_rot)
    end

    -- Enable cursor for GUI
    this.world.gui:getSystem():enableCursor(true)

    -- Create UI canvas
    canvas = this.world:createEntityEx({
        gui_canvas = {},
        gui_rect = {}
    })

    -- Create turn text
    turn_text = this.world:createEntityEx({
        gui_text = {
            text = "White's turn",
            font_size = 72,
            horizontal_align = LumixAPI.TextHAlign.CENTER
        },
        gui_rect = {
            left_relative = 0.5,
            right_relative = 0.5,
            left_points = -300,
            right_points = 300,
            top_points = 10,
            bottom_points = 100
        }
    })
    turn_text.parent = canvas
    turn_text.gui_text.font = "/engine/editor/fonts/notosans-bold.ttf"

    undo_button = this.world:createEntityEx({
        gui_button = {},
        gui_rect = {
            left_points = 10,
            right_points = 370,
            right_relative = 0,
            bottom_points = 10,
            top_points = -130,
            top_relative = 1
        },
        gui_image = { color = {0, 0, 0, 0.6} },
        gui_text = {
            text = "Undo",
            font_size = 66,
            font = "/engine/editor/fonts/notosans-bold.ttf",
            horizontal_align = LumixAPI.TextHAlign.CENTER,
            vertical_align = LumixAPI.TextVAlign.MIDDLE
        },
        lua_script = {},
        parent = canvas
    })
    undo_button.lua_script.scripts:add()
    undo_button.lua_script[1].onButtonClicked = function()
        undoMove()
    end

    restart_button = this.world:createEntityEx({
        gui_button = {},
        gui_rect = {
            left_points = 380,
            right_points = 740,
            right_relative = 0,
            bottom_points = 10,
            top_points = -130,
            top_relative = 1
        },
        gui_image = { color = {0, 0, 0, 0.6} },
        gui_text = {
            text = "Restart",
            font_size = 66,
            font = "/engine/editor/fonts/notosans-bold.ttf",
            horizontal_align = LumixAPI.TextHAlign.CENTER,
            vertical_align = LumixAPI.TextVAlign.MIDDLE
        },
        lua_script = {},
        parent = canvas
    })
    restart_button.lua_script.scripts:add()
    restart_button.lua_script[1].onButtonClicked = function()
        restartGame()
    end

    -- Create board squares
    createBoard()

    -- Create pieces
    createPieces()

    LumixAPI.logInfo("Chess game initialized")
end

function createBoard()
    local entity = this.world:createEntityEx{
        name = "board",
        position = {0, 0, 0},
        rotation = MODEL_ROT_X90,
        scale = {CHESS_MODEL_SCALE, CHESS_MODEL_SCALE, CHESS_MODEL_SCALE},
        model_instance = { source = BOARD_MODEL }
    }

    if entity and entity.model_instance then
        -- Force the correct board material (so it doesn't depend on FBX-imported materials).
        entity.model_instance:setMaterialOverride(0, MAT_BOARD)
    end
end

function createPieces()
    -- White pieces
    createPiece(PIECE_TYPES.ROOK, WHITE, 1, 1)
    createPiece(PIECE_TYPES.KNIGHT, WHITE, 2, 1)
    createPiece(PIECE_TYPES.BISHOP, WHITE, 3, 1)
    createPiece(PIECE_TYPES.QUEEN, WHITE, 4, 1)
    createPiece(PIECE_TYPES.KING, WHITE, 5, 1)
    createPiece(PIECE_TYPES.BISHOP, WHITE, 6, 1)
    createPiece(PIECE_TYPES.KNIGHT, WHITE, 7, 1)
    createPiece(PIECE_TYPES.ROOK, WHITE, 8, 1)
    for i = 1, 8 do
        createPiece(PIECE_TYPES.PAWN, WHITE, i, 2)
    end

    -- Black pieces
    createPiece(PIECE_TYPES.ROOK, BLACK, 1, 8)
    createPiece(PIECE_TYPES.KNIGHT, BLACK, 2, 8)
    createPiece(PIECE_TYPES.BISHOP, BLACK, 3, 8)
    createPiece(PIECE_TYPES.QUEEN, BLACK, 4, 8)
    createPiece(PIECE_TYPES.KING, BLACK, 5, 8)
    createPiece(PIECE_TYPES.BISHOP, BLACK, 6, 8)
    createPiece(PIECE_TYPES.KNIGHT, BLACK, 7, 8)
    createPiece(PIECE_TYPES.ROOK, BLACK, 8, 8)
    for i = 1, 8 do
        createPiece(PIECE_TYPES.PAWN, BLACK, i, 7)
    end
end

local function applyPiecePosition(piece)
    local base = piece.base_pos
    for _, part in ipairs(piece.parts) do
        local o = part.offset
        if part.entity then
            part.entity.position = {base[1] + o[1], piece.current_y + o[2], base[3] + o[3]}
        end
    end
end

local function removePieceFromList(piece)
    for i, p in ipairs(pieces) do
        if p == piece then
            table.remove(pieces, i)
            return
        end
    end
end

local function addPieceToList(piece)
    table.insert(pieces, piece)
end

local function createModelPart(model, position, material)
    local entity = this.world:createEntityEx{
        position = position,
        rotation = MODEL_ROT_X90,
        scale = {CHESS_MODEL_SCALE, CHESS_MODEL_SCALE, CHESS_MODEL_SCALE},
        model_instance = { source = model }
    }

    if entity and entity.model_instance and material then
        entity.model_instance:setMaterialOverride(0, material)
    end
    return entity
end

local function getMeshNameForPiece(piece_type, color, x, z)
    if piece_type == PIECE_TYPES.PAWN then
        local base = (color == WHITE) and 0 or 8
        return string.format("Pawn_low.%03d", base + (x - 1))
    end

    if piece_type == PIECE_TYPES.ROOK then
        if color == WHITE then
            return (x == 1) and "Rook_low.000" or "Rook_low.001"
        else
            return (x == 1) and "Rook_low.002" or "Rook_low.003"
        end
    end

    if piece_type == PIECE_TYPES.KNIGHT then
        if color == WHITE then
            return (x == 2) and "Knight_low.000" or "Knight_low.001"
        else
            return (x == 2) and "Knight_low.002" or "Knight_low.003"
        end
    end

    if piece_type == PIECE_TYPES.BISHOP then
        if color == WHITE then
            return (x == 3) and "Bishop_low.000" or "Bishop_low.001"
        else
            return (x == 3) and "Bishop_low.002" or "Bishop_low.003"
        end
    end

    if piece_type == PIECE_TYPES.QUEEN then
        return (color == WHITE) and "Queen_low.000" or "Queen_low.001"
    end

    if piece_type == PIECE_TYPES.KING then
        return (color == WHITE) and "King_low.000" or "King_low.001"
    end

    return nil
end

local function buildChessPieceParts(piece_type, color, base_pos, x, z)
    local mesh_name = getMeshNameForPiece(piece_type, color, x, z)
    if not mesh_name then
        return {}
    end

    local material = (color == WHITE) and MAT_PIECES_WHITE or MAT_PIECES_BLACK
    local entity = createModelPart(chessModel(mesh_name), base_pos, material)
    return { { entity = entity, offset = {0, 0, 0} } }
end

function createPiece(type, color, x, z)
    local position = squareToBasePos(x, z)

    local parts = buildChessPieceParts(type, color, position, x, z)
    local root_entity = parts[1] and parts[1].entity or nil

    -- Store piece data
    local piece = {
        entity = root_entity,
        parts = parts,
        type = type,
        color = color,
        x = x,
        z = z,
        base_pos = {position[1], position[2], position[3]},
        current_y = PIECE_HEIGHT + PIECE_Y_OFFSET,
        animating = false,
        anim_start_pos = nil,
        anim_target_pos = nil,
        anim_time = 0,
        anim_duration = 0.5
    }
    board[x][z] = piece
    table.insert(pieces, piece)

    applyPiecePosition(piece)
end

function onInputEvent(event)
    -- Ignore input during AI turn or when game is over
    if (AI_ENABLED and current_turn == AI_PLAYER) or game_over then
        return
    end
    
    if event.device and event.device.type == "mouse" then
        if event.type == "axis" then
            mouse_pos[1] = event.x_abs
            mouse_pos[2] = event.y_abs
            return
        end

        if event.type == "button" then
            if not camera_entity or not camera_entity.camera then
                return
            end

            if isAnyPieceAnimating() then
                LumixAPI.logInfo("Input ignored: piece animating, turn " .. (current_turn == WHITE and "White" or "Black"))
                return
            end

            -- Button events contain x/y too; use them as a fallback if we didn't get an axis event yet.
            if event.x and event.y then
                mouse_pos[1] = event.x
                mouse_pos[2] = event.y
            end

            local ray = camera_entity.camera:getRay({mouse_pos[1], mouse_pos[2]})
            local hit_pos = nil

            -- Compute intersection with board plane at y = 0.308
            if ray.dir[2] ~= 0 then
                local t = (0.308 - ray.origin[2]) / ray.dir[2]
                if t >= 0 then
                    hit_pos = {
                        ray.origin[1] + ray.dir[1] * t,
                        0.308,
                        ray.origin[3] + ray.dir[3] * t
                    }
                end
            end

            if not hit_pos then
                return
            end

            local target_x, target_z = getSquareFromPosition(hit_pos)
            if not target_x or not target_z then
                if not event.down and dragging and dragged_piece then
                    if dragged_piece.last_valid_square then
                        local lx = dragged_piece.last_valid_square[1]
                        local lz = dragged_piece.last_valid_square[2]
                        movePiece(dragged_piece, lx, lz)
                        LumixAPI.logInfo("Invalid drop, snapping to last valid square " .. lx .. "," .. lz .. " (turn " .. (current_turn == WHITE and "White" or "Black") .. ")")
                        dragging = false
                        dragged_piece = nil
                    else
                        local home = squareToBasePos(dragged_piece.x, dragged_piece.z)
                        dragged_piece.target_base_pos = {home[1], home[2], home[3]}
                        dragged_piece.last_valid_base_pos = {home[1], home[2], home[3]}
                        dragged_piece.target_current_y = PIECE_HEIGHT + PIECE_Y_OFFSET
                        dropping = true
                        LumixAPI.logInfo("Invalid move, dropping back (turn " .. (current_turn == WHITE and "White" or "Black") .. ")")
                        dragging = false
                    end
                end
                return
            end

            if event.down then
                -- Start drag if clicking on a piece
                local clicked_piece = board[target_x][target_z]
                if clicked_piece and clicked_piece.color == current_turn and not clicked_piece.animating then
                    dragging = true
                    dragged_piece = clicked_piece
                    -- Set initial targets for smooth lift
                    dragged_piece.target_base_pos = {clicked_piece.base_pos[1], clicked_piece.base_pos[2], clicked_piece.base_pos[3]}
                    dragged_piece.last_valid_base_pos = {clicked_piece.base_pos[1], clicked_piece.base_pos[2], clicked_piece.base_pos[3]}
                    dragged_piece.last_valid_square = nil
                    dragged_piece.target_current_y = PIECE_HEIGHT + PIECE_Y_OFFSET + DRAG_LIFT
                    LumixAPI.logInfo("Started dragging piece at " .. clicked_piece.x .. "," .. clicked_piece.z .. " (turn " .. (current_turn == WHITE and "White" or "Black") .. ")")
                end
            else
                -- Mouse up: end drag and attempt move
                if dragging and dragged_piece then
                    if not dragged_piece.animating and isLegalMove(dragged_piece, dragged_piece.x, dragged_piece.z, target_x, target_z) then
                        movePiece(dragged_piece, target_x, target_z)
                        LumixAPI.logInfo("Moved piece to " .. target_x .. "," .. target_z .. " (turn " .. (current_turn == WHITE and "White" or "Black") .. ")")
                        dragging = false
                        dragged_piece = nil
                    else
                        -- Invalid move, start dropping
                        if dragged_piece.last_valid_square then
                            local lx = dragged_piece.last_valid_square[1]
                            local lz = dragged_piece.last_valid_square[2]
                            movePiece(dragged_piece, lx, lz)
                            LumixAPI.logInfo("Invalid drop, snapping to last valid square " .. lx .. "," .. lz .. " (turn " .. (current_turn == WHITE and "White" or "Black") .. ")")
                            dragging = false
                            dragged_piece = nil
                        else
                            local home = squareToBasePos(dragged_piece.x, dragged_piece.z)
                            dragged_piece.target_base_pos = {home[1], home[2], home[3]}
                            dragged_piece.last_valid_base_pos = {home[1], home[2], home[3]}
                            dragged_piece.target_current_y = PIECE_HEIGHT + PIECE_Y_OFFSET
                            dropping = true
                            LumixAPI.logInfo("Invalid move, dropping back (turn " .. (current_turn == WHITE and "White" or "Black") .. ")")
                            dragging = false  -- Stop dragging, start dropping
                        end
                    end
                end
            end
        end
    end
end

function getPieceAtEntity(entity)
    if type(entity) ~= "table" then return nil end
    local entity_id = entity._entity
    if not entity_id then return nil end
    for _, piece in ipairs(pieces) do
        if piece.entity and piece.entity._entity == entity_id then
            return piece
        end
    end
    return nil
end

function getSquareFromPosition(pos)
    local x = math.floor((pos[1] + (BOARD_SIZE / 2) * SQUARE_SIZE) / SQUARE_SIZE) + 1
    local z = math.floor((pos[3] + (BOARD_SIZE / 2) * SQUARE_SIZE) / SQUARE_SIZE) + 1
    if x >= 1 and x <= BOARD_SIZE and z >= 1 and z <= BOARD_SIZE then
        return x, z
    end
    return nil, nil
end

function isValidMove(piece, from_x, from_z, to_x, to_z)
    if from_x == to_x and from_z == to_z then return false end
    if board[to_x][to_z] and board[to_x][to_z].color == piece.color then return false end

    local dx = to_x - from_x
    local dz = to_z - from_z

    if piece.type == PIECE_TYPES.PAWN then
        local direction = (piece.color == WHITE) and 1 or -1
        if dz == direction and dx == 0 and not board[to_x][to_z] then return true end
        if dz == direction and math.abs(dx) == 1 and board[to_x][to_z] and board[to_x][to_z].color ~= piece.color then return true end
        -- Initial double move
        if (piece.color == WHITE and from_z == 2) or (piece.color == BLACK and from_z == 7) then
            if dz == 2 * direction and dx == 0 and not board[to_x][to_z] and not board[to_x][from_z + direction] then return true end
        end
    elseif piece.type == PIECE_TYPES.ROOK then
        if (dx == 0 or dz == 0) and isPathClear(from_x, from_z, to_x, to_z) then return true end
    elseif piece.type == PIECE_TYPES.KNIGHT then
        if (math.abs(dx) == 2 and math.abs(dz) == 1) or (math.abs(dx) == 1 and math.abs(dz) == 2) then return true end
    elseif piece.type == PIECE_TYPES.BISHOP then
        if math.abs(dx) == math.abs(dz) and isPathClear(from_x, from_z, to_x, to_z) then return true end
    elseif piece.type == PIECE_TYPES.QUEEN then
        if ((dx == 0 or dz == 0) or math.abs(dx) == math.abs(dz)) and isPathClear(from_x, from_z, to_x, to_z) then return true end
    elseif piece.type == PIECE_TYPES.KING then
        if math.abs(dx) <= 1 and math.abs(dz) <= 1 then return true end
    end

    return false
end

withTemporaryMove = function(piece, from_x, from_z, to_x, to_z, callback)
    local captured = board[to_x][to_z]
    local captured_index = nil

    if captured then
        for i, p in ipairs(pieces) do
            if p == captured then
                captured_index = i
                table.remove(pieces, i)
                break
            end
        end
    end

    board[from_x][from_z] = nil
    board[to_x][to_z] = piece
    piece.x = to_x
    piece.z = to_z

    local result = callback()

    board[to_x][to_z] = captured
    board[from_x][from_z] = piece
    piece.x = from_x
    piece.z = from_z

    if captured then
        if captured_index then
            table.insert(pieces, captured_index, captured)
        else
            table.insert(pieces, captured)
        end
    end

    return result
end

function wouldMoveLeaveKingInCheck(piece, from_x, from_z, to_x, to_z)
    return withTemporaryMove(piece, from_x, from_z, to_x, to_z, function()
        return isKingInCheck(piece.color)
    end)
end

function isLegalMove(piece, from_x, from_z, to_x, to_z)
    if not isValidMove(piece, from_x, from_z, to_x, to_z) then
        return false
    end
    if wouldMoveLeaveKingInCheck(piece, from_x, from_z, to_x, to_z) then
        return false
    end
    return true
end

function isPathClear(from_x, from_z, to_x, to_z)
    local dx = (to_x > from_x) and 1 or (to_x < from_x) and -1 or 0
    local dz = (to_z > from_z) and 1 or (to_z < from_z) and -1 or 0
    local x, z = from_x + dx, from_z + dz
    while x ~= to_x or z ~= to_z do
        if board[x][z] then return false end
        x = x + dx
        z = z + dz
    end
    return true
end

local function recordUndoMove(piece, from_x, from_z, to_x, to_z)
    local captured = board[to_x][to_z]
    local captured_data = captured or nil
    table.insert(undo_stack, {
        piece = piece,
        from_x = from_x,
        from_z = from_z,
        to_x = to_x,
        to_z = to_z,
        captured = captured_data,
        prev_turn = current_turn
    })
end

undoMove = function()
    if #undo_stack == 0 then
        LumixAPI.logInfo("Undo: no moves to undo")
        return
    end

    if dragging or dropping or isAnyPieceAnimating() then
        LumixAPI.logInfo("Undo: blocked during animation or drag")
        return
    end

    ai_thinking = false
    ai_timer = 0
    game_over = false

    local move = table.remove(undo_stack)
    local piece = move.piece

    if not piece then
        return
    end

    board[move.to_x][move.to_z] = nil
    board[move.from_x][move.from_z] = piece

    piece.x = move.from_x
    piece.z = move.from_z
    piece.animating = false
    piece.anim_time = 0

    local home = squareToBasePos(move.from_x, move.from_z)
    piece.base_pos = {home[1], home[2], home[3]}
    piece.current_y = PIECE_HEIGHT + PIECE_Y_OFFSET
    applyPiecePosition(piece)

    if move.captured then
        local captured = move.captured
        captured.x = move.to_x
        captured.z = move.to_z
        captured.animating = false
        captured.anim_time = 0

        local captured_home = squareToBasePos(move.to_x, move.to_z)
        captured.base_pos = {captured_home[1], captured_home[2], captured_home[3]}
        captured.current_y = PIECE_HEIGHT + PIECE_Y_OFFSET
        addPieceToList(captured)
        board[move.to_x][move.to_z] = captured
        applyPiecePosition(captured)
    end

    dragging = false
    dropping = false
    dragged_piece = nil

    current_turn = move.prev_turn
    updateTurnText()

    if AI_ENABLED and current_turn == AI_PLAYER and not game_over then
        ai_timer = 0
        ai_thinking = true
        if isKingInCheck(AI_PLAYER) then
            turn_text.gui_text.text = "AI is in check! Thinking..."
        else
            turn_text.gui_text.text = "AI is thinking..."
        end
    end
end

restartGame = function()
    if dragging or dropping or isAnyPieceAnimating() then
        LumixAPI.logInfo("Restart: blocked during animation or drag")
        return
    end

    ai_thinking = false
    ai_timer = 0
    game_over = false

    for _, piece in ipairs(pieces) do
        for _, part in ipairs(piece.parts) do
            if part.entity then
                part.entity:destroy()
            end
        end
    end

    pieces = {}
    selected_piece = nil
    hovered_piece = nil
    hover_time = 0
    dragging = false
    dropping = false
    dragged_piece = nil
    undo_stack = {}

    for i = 1, BOARD_SIZE do
        board[i] = board[i] or {}
        for j = 1, BOARD_SIZE do
            board[i][j] = nil
        end
    end

    current_turn = WHITE
    createPieces()
    updateTurnText()
    LumixAPI.logInfo("Chess game restarted")
end

function movePiece(piece, to_x, to_z)
    recordUndoMove(piece, piece.x, piece.z, to_x, to_z)
    -- Capture if there's a piece
    if board[to_x][to_z] then
        local captured = board[to_x][to_z]
        removePieceFromList(captured)
        captured.current_y = -1000
        captured.base_pos = {0, -1000, 0}
        applyPiecePosition(captured)
    end

    -- Update board
    board[piece.x][piece.z] = nil
    board[to_x][to_z] = piece
    piece.x = to_x
    piece.z = to_z

    -- Start animation
    local target_pos = squareToBasePos(to_x, to_z)
    piece.anim_start_pos = {piece.base_pos[1], piece.current_y, piece.base_pos[3]}
    piece.anim_target_pos = {target_pos[1], PIECE_HEIGHT + PIECE_Y_OFFSET, target_pos[3]}
    if piece.current_y > piece.anim_target_pos[2] + 0.01 then
        piece.anim_lift = 0
    else
        piece.anim_lift = (current_turn == AI_PLAYER) and 1.0 or 0.5  -- Higher lift for AI moves
    end
    piece.anim_time = 0
    piece.anim_duration = (current_turn == AI_PLAYER) and 1.0 or 0.5  -- Slower animation for AI moves
    piece.animating = true
    -- Don't set base_pos yet, animation will handle it
end

function switchTurn()
    current_turn = (current_turn == WHITE) and BLACK or WHITE
    updateTurnText()
    LumixAPI.logInfo("Turn switched to " .. (current_turn == WHITE and "White" or "Black"))
    
    -- Check for game over
    if checkGameOver() then
        game_over = true
        return
    end
    
    -- Start AI thinking if it's AI's turn
    if AI_ENABLED and current_turn == AI_PLAYER and not game_over then
        ai_timer = 0
        ai_thinking = true
        if isKingInCheck(AI_PLAYER) then
            turn_text.gui_text.text = "AI is in check! Thinking..."
        else
            turn_text.gui_text.text = "AI is thinking..."
        end
    end
end

function update(td)
    if not camera_entity or not camera_entity.camera then
        return
    end

    hover_time = hover_time + td

    local ray = camera_entity.camera:getRay({mouse_pos[1], mouse_pos[2]})
    local hit_pos = nil

    -- Compute intersection with board plane at y = 0.308
    if ray.dir[2] ~= 0 then
        local t = (0.308 - ray.origin[2]) / ray.dir[2]
        if t >= 0 then
            hit_pos = {
                ray.origin[1] + ray.dir[1] * t,
                0.308,
                ray.origin[3] + ray.dir[3] * t
            }
        end
    end

    if hit_pos then
        local hx, hz = getSquareFromPosition(hit_pos)
        if hx and hz then
            local candidate = board[hx][hz]
            if candidate and candidate.color == current_turn and not dragging and not dropping and (not AI_ENABLED or current_turn ~= AI_PLAYER) then
                hovered_piece = candidate
            else
                hovered_piece = nil
            end
        else
            hovered_piece = nil
        end
    else
        hovered_piece = nil
    end

    -- Handle dragging snapping
    if dragging and dragged_piece and hit_pos then
        local target_x, target_z = getSquareFromPosition(hit_pos)
        if target_x and target_z then
            if isLegalMove(dragged_piece, dragged_piece.x, dragged_piece.z, target_x, target_z) then
                -- Set targets to valid target position
                local pos = squareToBasePos(target_x, target_z)
                dragged_piece.target_base_pos = {pos[1], pos[2], pos[3]}
                dragged_piece.last_valid_base_pos = {pos[1], pos[2], pos[3]}
                dragged_piece.last_valid_square = {target_x, target_z}
                dragged_piece.target_current_y = PIECE_HEIGHT + PIECE_Y_OFFSET + DRAG_LIFT
            else
                -- Set targets to original position
                if dragged_piece.last_valid_base_pos then
                    dragged_piece.target_base_pos = {dragged_piece.last_valid_base_pos[1], dragged_piece.last_valid_base_pos[2], dragged_piece.last_valid_base_pos[3]}
                else
                    local orig_x = (dragged_piece.x - 1) * SQUARE_SIZE - (BOARD_SIZE / 2 - 0.5) * SQUARE_SIZE
                    local orig_z = (dragged_piece.z - 1) * SQUARE_SIZE - (BOARD_SIZE / 2 - 0.5) * SQUARE_SIZE
                    dragged_piece.target_base_pos = {orig_x, PIECE_HEIGHT + PIECE_Y_OFFSET, orig_z}
                end
                dragged_piece.target_current_y = PIECE_HEIGHT + PIECE_Y_OFFSET + DRAG_LIFT
            end
        end
    end

    -- Interpolate dragged piece position
    if (dragging or dropping) and dragged_piece and dragged_piece.target_base_pos then
        local lerp_t = math.min(1, td * SNAP_LERP_SPEED)
        for i = 1, 3 do
            dragged_piece.base_pos[i] = dragged_piece.base_pos[i] + (dragged_piece.target_base_pos[i] - dragged_piece.base_pos[i]) * lerp_t
        end
        dragged_piece.current_y = dragged_piece.current_y + (dragged_piece.target_current_y - dragged_piece.current_y) * lerp_t
        applyPiecePosition(dragged_piece)
        -- Check if dropping is done
        if dropping then
            local done_y = math.abs(dragged_piece.current_y - dragged_piece.target_current_y) < 0.01
            local done_x = math.abs(dragged_piece.base_pos[1] - dragged_piece.target_base_pos[1]) < 0.01
            local done_z = math.abs(dragged_piece.base_pos[3] - dragged_piece.target_base_pos[3]) < 0.01
            if done_y and done_x and done_z then
                dropping = false
                dragged_piece = nil
            end
        end
    end

    local bob = math.sin(hover_time * HOVER_BOB_SPEED) * HOVER_BOB_AMPLITUDE
    for _, piece in ipairs(pieces) do
        if piece ~= dragged_piece then  -- Skip dragged piece, handled separately
            local base = piece.base_pos
            if base then
                local target_y = base[2]
                if piece == hovered_piece and not piece.animating then
                    target_y = base[2] + HOVER_LIFT + bob
                end
                local t = math.min(1, td * HOVER_SMOOTH)
                piece.current_y = piece.current_y + (target_y - piece.current_y) * t
                applyPiecePosition(piece)
            end
        end

        -- Handle animation
        if piece.animating then
            piece.anim_time = piece.anim_time + td
            local t = math.min(1, piece.anim_time / piece.anim_duration)
            -- Smooth step easing
            t = t * t * (3 - 2 * t)
            local lift = (piece.anim_lift or 0.5) * math.sin(t * math.pi)  -- Arc motion
            local current_pos = {
                piece.anim_start_pos[1] + (piece.anim_target_pos[1] - piece.anim_start_pos[1]) * t,
                piece.anim_start_pos[2] + (piece.anim_target_pos[2] - piece.anim_start_pos[2]) * t + lift,
                piece.anim_start_pos[3] + (piece.anim_target_pos[3] - piece.anim_start_pos[3]) * t
            }
            piece.current_y = current_pos[2]
            piece.base_pos[1] = current_pos[1]
            piece.base_pos[3] = current_pos[3]
            applyPiecePosition(piece)

            if piece.anim_time >= piece.anim_duration then
                piece.animating = false
                piece.current_y = piece.anim_target_pos[2]
                piece.base_pos = {piece.anim_target_pos[1], piece.anim_target_pos[2], piece.anim_target_pos[3]}
                applyPiecePosition(piece)
                switchTurn()
            end
        end
    end

    -- Handle AI thinking and moves
    if ai_thinking and not game_over then
        ai_timer = ai_timer + td
        if ai_timer >= AI_THINK_TIME then
            ai_thinking = false
            makeAIMove()
        end
    end
end
