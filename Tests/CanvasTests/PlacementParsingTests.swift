import CanvasCore
import Foundation
import Testing

@Suite struct PlacementParsingTests {
    @Test func defaultsWhenNothingIsGiven() throws {
        let defaults = try placement(#"{"cmd":"show","id":"x","source":"hi","width":null}"#)
        #expect(defaults.given.isEmpty)
        #expect(defaults == Placement())
        #expect(defaults.position == .center && defaults.at == nil && defaults.screen == .mouse)
        #expect(defaults.margin == nil && defaults.height == nil && defaults.stack == nil)
        #expect(defaults.width == .points(720))
        #expect(defaults.minHeight == .points(80))
        #expect(defaults.maxHeight == .percent(85))
        #expect(defaults.resizable && !defaults.pin && !defaults.clickThrough && !defaults.forget)
        #expect(defaults.level == .floating && defaults.spaces == .all && defaults.opacity == 1)
        #expect(defaults.restoresRememberedFrame)
    }

    @Test func readsEveryField() throws {
        let read = try placement("""
            {"position":"bottom-left","at":{"x":-24,"y":"10%"},"screen":"DELL","margin":8,"width":"40%",
             "height":300,"minHeight":100,"maxHeight":"60%","resizable":false,"level":"top","spaces":"current",
             "pin":true,"clickThrough":true,"opacity":0.85,"stack":"notes","forget":true}
            """)
        #expect(read.given == Set(Placement.Field.allCases))
        #expect(read.position == .bottomLeft)
        #expect(read.at == AtPoint(x: .points(-24), y: .percent(10)))
        #expect(read.screen == .name("DELL"))
        #expect(read.margin == 8)
        #expect(read.width == .percent(40) && read.height == .points(300))
        #expect(read.minHeight == .points(100) && read.maxHeight == .percent(60))
        #expect(!read.resizable && read.level == .top && read.spaces == .current)
        #expect(read.pin && read.clickThrough && read.forget)
        #expect(read.opacity == 0.85 && read.stack == "notes")
    }

    @Test(arguments: [
        ("center", Placement.Position.center), ("top", .top), ("bottom", .bottom), ("left", .left),
        ("right", .right), ("top-left", .topLeft), ("top-right", .topRight), ("bottom-left", .bottomLeft),
        ("bottom-right", .bottomRight), ("mouse", .mouse)
    ])
    func readsEveryPosition(raw: String, expected: Placement.Position) throws {
        #expect(try placement(#"{"position":"\#(raw)"}"#).position == expected)
    }

    @Test(arguments: [
        (#"640"#, Length(magnitude: 640, unit: .points, negative: false)),
        (#"12.5"#, Length(magnitude: 12.5, unit: .points, negative: false)),
        (#"-24"#, Length(magnitude: 24, unit: .points, negative: true)),
        (#""50%""#, Length(magnitude: 50, unit: .percent, negative: false)),
        (#""-10%""#, Length(magnitude: 10, unit: .percent, negative: true)),
        (#""-0""#, Length(magnitude: 0, unit: .points, negative: true)),
        (#""-0%""#, Length(magnitude: 0, unit: .percent, negative: true)),
        (#"" 30 ""#, Length(magnitude: 30, unit: .points, negative: false))
    ])
    func readsLengths(literal: String, expected: Length) throws {
        #expect(try placement(#"{"at":{"x":\#(literal),"y":0}}"#).at?.x == expected)
    }

    @Test(arguments: [
        (#""mouse""#, ScreenSelector.mouse), (#""Main""#, .main), (#""focused""#, .focused),
        (#""2""#, .index(2)), (#"3"#, .index(3)), (#""dell""#, .name("dell")), (#""LG 4K""#, .name("LG 4K"))
    ])
    func readsScreens(literal: String, expected: ScreenSelector) throws {
        #expect(try placement(#"{"screen":\#(literal)}"#).screen == expected)
    }

    @Test(arguments: [
        #"{"position":"middle"}"#, #"{"position":3}"#, #"{"position":"Top"}"#,
        #"{"at":"10,20"}"#, #"{"at":{"x":1}}"#, #"{"at":{"x":"a","y":1}}"#, #"{"at":{"x":true,"y":1}}"#,
        #"{"at":{"x":"5px","y":1}}"#, #"{"screen":""}"#, #"{"screen":"0"}"#, #"{"screen":0}"#,
        #"{"screen":1.5}"#, #"{"screen":true}"#, #"{"margin":-1}"#, #"{"margin":"10"}"#, #"{"margin":false}"#,
        #"{"width":-5}"#, #"{"width":0}"#, #"{"width":"abc"}"#, #"{"width":"-50%"}"#, #"{"width":true}"#,
        #"{"height":0}"#, #"{"minHeight":0}"#, #"{"maxHeight":"-1%"}"#, #"{"maxHeight":"0%"}"#,
        #"{"opacity":1.5}"#, #"{"opacity":-0.1}"#, #"{"opacity":"0.5"}"#, #"{"level":"high"}"#,
        #"{"spaces":"some"}"#, #"{"pin":"yes"}"#, #"{"pin":1}"#, #"{"clickThrough":0}"#,
        #"{"resizable":"true"}"#, #"{"forget":1}"#, #"{"stack":""}"#, #"{"stack":5}"#, #"{"stack":"  "}"#
    ])
    func rejectsInvalidValues(request: String) {
        #expect(throws: RequestError.self) { try placement(request) }
    }

    @Test func errorsNameTheFieldAndTheChoices() {
        #expect(message(#"{"position":"middle"}"#) == """
            invalid position "middle": expected one of center, top, bottom, left, right, top-left, top-right, \
            bottom-left, bottom-right, mouse
            """)
        #expect(message(#"{"opacity":2}"#) == "invalid opacity 2: expected a number from 0 to 1")
        #expect(message(#"{"width":"-50%"}"#) == #"invalid width "-50%": expected a positive number or "N%""#)
        #expect(message(#"{"pin":1}"#) == "invalid pin 1: expected true or false")
    }

    private func message(_ request: String) -> String? {
        do {
            _ = try placement(request)
            return nil
        } catch let error as RequestError {
            return error.message
        } catch {
            return "\(error)"
        }
    }

    @Test func givenIsKeptApartFromDefaults() throws {
        let explicit = try placement(#"{"width":720,"pin":false,"position":"center","screen":"mouse"}"#)
        #expect(explicit.given == [.width, .pin, .position, .screen])
        #expect(explicit.width == Placement().width && explicit.position == Placement().position)
        #expect(explicit != Placement())
        #expect(!explicit.restoresRememberedFrame)
    }

    @Test(arguments: [
        ("{}", true), (#"{"width":300,"screen":"main","opacity":0.5}"#, true),
        (#"{"position":"center"}"#, false), (#"{"at":{"x":0,"y":0}}"#, false), (#"{"stack":"notes"}"#, false),
        (#"{"forget":true}"#, false), (#"{"forget":false}"#, true)
    ])
    func restoresRememberedFrameOnlyWithoutPositionOrAt(request: String, restores: Bool) throws {
        #expect(try placement(request).restoresRememberedFrame == restores)
    }

    @Test(arguments: [
        ("{}", Placement.Level.floating, Placement.Spaces.all),
        (#"{"level":"normal","spaces":"current"}"#, .normal, .current),
        (#"{"pin":true,"level":"normal","spaces":"current"}"#, .floating, .all),
        (#"{"pin":true,"level":"top"}"#, .top, .all)
    ])
    func pinKeepsThePanelUpOnAllSpaces(request: String, level: Placement.Level, spaces: Placement.Spaces) throws {
        let read = try placement(request)
        #expect(read.effectiveLevel == level && read.effectiveSpaces == spaces)
    }

    @Test func pinnedPanelsIgnoreEscape() throws {
        #expect(try placement("{}").closesOnEscape)
        #expect(try !placement(#"{"pin":true}"#).closesOnEscape)
    }
}
