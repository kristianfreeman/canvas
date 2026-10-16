import CanvasCore
import CoreGraphics
import Testing

struct FrameCase: CustomTestStringConvertible, Sendable {
    let screen: ScreenInfo
    let request: String
    var content: CGFloat? = 400
    var mouse = CGPoint.zero
    let expected: CGRect

    var testDescription: String { "\(screen.name) \(request) content=\(content.map { "\($0)" } ?? "nil")" }
}

/// `rect(x, y, width, height)`, short enough for one case per line.
private func rect(_ values: CGFloat...) -> CGRect {
    precondition(values.count == 4, "rect takes x, y, width, height")
    return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
}

/// Laptop: visible frame (0, 0, 1512, 944). Width 720 and content 400
/// unless a case says otherwise. Centered x = (1512 - 720) / 2 = 396,
/// centered y = (944 - 400) / 2 = 272, right x = 1512 - 24 - 720 = 768,
/// top-corner y = 944 - 24 - 400 = 520, `top` y = 944 - 64 - 400 = 480.
private let laptopPresets: [FrameCase] = [
    FrameCase(screen: Screens.laptop, request: "{}", expected: rect(396, 272, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"center"}"#, expected: rect(396, 272, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"top"}"#, expected: rect(396, 480, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"bottom"}"#, expected: rect(396, 24, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"left"}"#, expected: rect(24, 272, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"right"}"#, expected: rect(768, 272, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"top-left"}"#, expected: rect(24, 520, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"top-right"}"#, expected: rect(768, 520, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"bottom-left"}"#, expected: rect(24, 24, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"bottom-right"}"#, expected: rect(768, 24, 720, 400)),
    FrameCase(screen: Screens.laptop, request: "{}", content: nil, expected: rect(396, 372, 720, 200)),
    FrameCase(screen: Screens.laptop, request: "{}", content: 2000, expected: rect(396, 71, 720, 802)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"top"}"#, content: 2000,
              expected: rect(396, 78, 720, 802)),
    FrameCase(screen: Screens.laptop, request: "{}", content: 10.2, expected: rect(396, 432, 720, 80)),
    FrameCase(screen: Screens.laptop, request: "{}", content: 400.2, expected: rect(396, 271, 720, 401))
]

private let laptopMargins: [FrameCase] = [
    FrameCase(screen: Screens.laptop, request: #"{"position":"top","margin":0}"#, expected: rect(396, 544, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"top","margin":100}"#,
              expected: rect(396, 444, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"bottom","margin":0}"#, expected: rect(396, 0, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"left","margin":10}"#, expected: rect(10, 272, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"bottom-right","margin":40}"#,
              expected: rect(752, 40, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"top-left","margin":0}"#,
              expected: rect(0, 544, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"center","margin":300}"#,
              expected: rect(396, 272, 720, 400))
]

private let laptopSizes: [FrameCase] = [
    FrameCase(screen: Screens.laptop, request: #"{"position":"right","width":500,"height":300}"#,
              expected: rect(988, 322, 500, 300)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"left","width":100}"#, expected: rect(24, 272, 240, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"width":3000}"#, expected: rect(0, 272, 1512, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"right","margin":0,"width":"50%","height":"100%"}"#,
              expected: rect(756, 0, 756, 944)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"top-left","width":"25%"}"#,
              expected: rect(24, 520, 378, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"height":"50%"}"#, expected: rect(396, 236, 720, 472)),
    FrameCase(screen: Screens.laptop, request: #"{"height":2000}"#, expected: rect(396, 0, 720, 944)),
    FrameCase(screen: Screens.laptop, request: #"{"maxHeight":"50%"}"#, content: 2000,
              expected: rect(396, 236, 720, 472)),
    FrameCase(screen: Screens.laptop, request: #"{"maxHeight":300}"#, expected: rect(396, 322, 720, 300)),
    FrameCase(screen: Screens.laptop, request: #"{"minHeight":500}"#, expected: rect(396, 222, 720, 500)),
    FrameCase(screen: Screens.laptop, request: #"{"minHeight":120,"height":100}"#,
              expected: rect(396, 412, 720, 120)),
    FrameCase(screen: Screens.laptop, request: #"{"minHeight":900,"maxHeight":300}"#,
              expected: rect(396, 322, 720, 300))
]

/// `at` measures from the visible frame's top-left, y down: a top edge at
/// y = 50 is 944 - 50 = 894 in AppKit coordinates.
private let laptopAt: [FrameCase] = [
    FrameCase(screen: Screens.laptop, request: #"{"at":{"x":100,"y":50}}"#, expected: rect(100, 494, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"at":{"x":-24,"y":24}}"#, expected: rect(768, 520, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"at":{"x":24,"y":-24}}"#, expected: rect(24, 24, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"at":{"x":-24,"y":-24}}"#, expected: rect(768, 24, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"at":{"x":"50%","y":"50%"}}"#, expected: rect(756, 72, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"at":{"x":"-10%","y":"-10%"}}"#,
              expected: rect(641, 94, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"at":{"x":1000,"y":0}}"#, expected: rect(792, 544, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"at":{"x":"-0","y":"0"}}"#, expected: rect(792, 544, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"at":{"x":"-0%","y":"-0%"}}"#, expected: rect(792, 0, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"at":{"x":-0.0,"y":-0.0}}"#, expected: rect(792, 0, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"at":{"x":0,"y":0}}"#, expected: rect(0, 544, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"bottom","at":{"x":0,"y":0}}"#,
              expected: rect(0, 544, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"margin":50,"at":{"x":0,"y":0}}"#,
              expected: rect(0, 544, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"at":{"x":-5000,"y":5000}}"#, expected: rect(0, 0, 720, 400))
]

/// Below-right of the cursor by 12 pt, flipped left or above when that
/// side runs off the visible frame.
private let laptopMouse: [FrameCase] = [
    FrameCase(screen: Screens.laptop, request: #"{"position":"mouse"}"#, mouse: CGPoint(x: 100, y: 900),
              expected: rect(112, 488, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"mouse"}"#, mouse: CGPoint(x: 1400, y: 100),
              expected: rect(668, 112, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"mouse"}"#, content: 900, mouse: CGPoint(x: 700, y: 500),
              expected: rect(712, 142, 720, 802)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"mouse"}"#, mouse: CGPoint(x: 1500, y: 940),
              expected: rect(768, 528, 720, 400)),
    FrameCase(screen: Screens.laptop, request: #"{"position":"mouse"}"#, mouse: CGPoint(x: -100, y: 500),
              expected: rect(0, 88, 720, 400))
]

/// External: visible frame (-2560, 0, 2560, 1415), so centered x is
/// -2560 + (2560 - 720) / 2 = -1640 and centered y is (1415 - 400) / 2,
/// rounded down, = 507.
private let externalCases: [FrameCase] = [
    FrameCase(screen: Screens.external, request: "{}", expected: rect(-1640, 507, 720, 400)),
    FrameCase(screen: Screens.external, request: #"{"position":"top"}"#, expected: rect(-1640, 951, 720, 400)),
    FrameCase(screen: Screens.external, request: #"{"position":"bottom"}"#, expected: rect(-1640, 24, 720, 400)),
    FrameCase(screen: Screens.external, request: #"{"position":"left"}"#, expected: rect(-2536, 507, 720, 400)),
    FrameCase(screen: Screens.external, request: #"{"position":"right"}"#, expected: rect(-744, 507, 720, 400)),
    FrameCase(screen: Screens.external, request: #"{"position":"top-left"}"#, expected: rect(-2536, 991, 720, 400)),
    FrameCase(screen: Screens.external, request: #"{"position":"bottom-right"}"#, expected: rect(-744, 24, 720, 400)),
    FrameCase(screen: Screens.external, request: "{}", content: 2000, expected: rect(-1640, 106, 720, 1202)),
    FrameCase(screen: Screens.external, request: #"{"position":"right","margin":0,"width":"50%","height":"100%"}"#,
              expected: rect(-1280, 0, 1280, 1415)),
    FrameCase(screen: Screens.external, request: #"{"at":{"x":"-10%","y":"10%"}}"#,
              expected: rect(-976, 874, 720, 400)),
    FrameCase(screen: Screens.external, request: #"{"at":{"x":100,"y":100}}"#, expected: rect(-2460, 915, 720, 400)),
    FrameCase(screen: Screens.external, request: #"{"width":"33%"}"#, expected: rect(-1702, 507, 844, 400)),
    FrameCase(screen: Screens.external, request: #"{"position":"mouse"}"#, mouse: CGPoint(x: -100, y: 50),
              expected: rect(-832, 62, 720, 400))
]

/// Portrait: visible frame (200, 982, 1080, 1895), right edge 1280, top
/// edge 2877. 85% of 1895 is 1610.75, so long pages are 1610 tall.
private let portraitCases: [FrameCase] = [
    FrameCase(screen: Screens.portrait, request: "{}", content: 2000, expected: rect(380, 1124, 720, 1610)),
    FrameCase(screen: Screens.portrait, request: #"{"position":"top"}"#, expected: rect(380, 2413, 720, 400)),
    FrameCase(screen: Screens.portrait, request: #"{"position":"bottom-left"}"#, expected: rect(224, 1006, 720, 400)),
    FrameCase(screen: Screens.portrait, request: #"{"position":"top-right"}"#, expected: rect(536, 2453, 720, 400)),
    FrameCase(screen: Screens.portrait, request: #"{"position":"right"}"#, expected: rect(536, 1729, 720, 400)),
    FrameCase(screen: Screens.portrait, request: #"{"width":"100%"}"#, expected: rect(200, 1729, 1080, 400)),
    FrameCase(screen: Screens.portrait, request: #"{"width":2000}"#, expected: rect(200, 1729, 1080, 400)),
    FrameCase(screen: Screens.portrait, request: #"{"at":{"x":"50%","y":"-50%"}}"#,
              expected: rect(560, 1929, 720, 400)),
    FrameCase(screen: Screens.portrait, request: #"{"maxHeight":"100%"}"#, content: 3000,
              expected: rect(380, 982, 720, 1895)),
    FrameCase(screen: Screens.portrait, request: #"{"position":"mouse"}"#, mouse: CGPoint(x: 700, y: 2000),
              expected: rect(200, 1588, 720, 400))
]

/// A 300x60 visible frame, where 1% of the height is 0.6 pt: percentage
/// sizes round down but never to zero, so the panel is 1 pt tall at
/// y = 30 - 0.5 rounded down = 29, and 720 wide capped at the full 300.
private let tiny = ScreenInfo(frame: rect(0, 0, 300, 60), visibleFrame: rect(0, 0, 300, 60), name: "tiny")
private let tinyCases: [FrameCase] = [
    FrameCase(screen: tiny, request: #"{"minHeight":"1%","maxHeight":"1%"}"#, expected: rect(0, 29, 300, 1)),
    FrameCase(screen: tiny, request: #"{"minHeight":"1%","height":"1%"}"#, expected: rect(0, 29, 300, 1))
]

@Suite struct PlacementGeometryTests {
    static let cases = laptopPresets + laptopMargins + laptopSizes + laptopAt + laptopMouse
        + externalCases + portraitCases + tinyCases

    @Test(arguments: cases)
    func placesFrame(_ test: FrameCase) throws {
        let frame = try placement(test.request).placedFrame(contentHeight: test.content, on: test.screen,
                                                            mouse: test.mouse)
        #expect(frame == test.expected)
    }

    @Test(arguments: [
        ("center", Anchor(.center, .center)), ("top", Anchor(.top, .center)), ("bottom", Anchor(.bottom, .center)),
        ("left", Anchor(.center, .left)), ("right", Anchor(.center, .right)), ("top-left", Anchor(.top, .left)),
        ("top-right", Anchor(.top, .right)), ("bottom-left", Anchor(.bottom, .left)),
        ("bottom-right", Anchor(.bottom, .right))
    ])
    func presetAnchors(position: String, expected: Anchor) throws {
        #expect(try placement(#"{"position":"\#(position)"}"#).presetAnchor == expected)
    }

    @Test(arguments: [
        (#"{"x":0,"y":0}"#, Anchor(.top, .left)), (#"{"x":-1,"y":5}"#, Anchor(.top, .right)),
        (#"{"x":"10%","y":-3}"#, Anchor(.bottom, .left)), (#"{"x":"-0%","y":"-0"}"#, Anchor(.bottom, .right))
    ])
    func atAnchors(at: String, expected: Anchor) throws {
        #expect(try placement(#"{"position":"bottom","at":\#(at)}"#).presetAnchor == expected)
    }

    @Test(arguments: [
        (CGPoint(x: 100, y: 900), CGFloat(400), Anchor(.top, .left)),
        (CGPoint(x: 1400, y: 100), CGFloat(400), Anchor(.bottom, .right)),
        (CGPoint(x: 700, y: 500), CGFloat(900), Anchor(.bottom, .left))
    ])
    func mouseAnchorIsTheEdgeNearestTheCursor(mouse: CGPoint, content: CGFloat, expected: Anchor) throws {
        let mousePlacement = try placement(#"{"position":"mouse"}"#)
        #expect(mousePlacement.presetAnchor == nil)
        let frame = mousePlacement.placedFrame(contentHeight: content, on: Screens.laptop, mouse: mouse)
        #expect(mousePlacement.anchor(for: frame, mouse: mouse) == expected)
    }
}
