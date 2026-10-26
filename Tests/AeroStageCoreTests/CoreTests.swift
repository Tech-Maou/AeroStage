import Foundation
import Testing
@testable import AeroStageCore

@Suite struct StageOrderTests {
    @Test func dynamicKeepsOrderAndAppendsNew() {
        var order = StageOrder(names: ["3", "1"])
        order.reconcile(with: ["1", "3", "2"], mode: .dynamic)
        #expect(order.names == ["3", "1", "2"])
    }

    @Test func dynamicClosesGaps() {
        var order = StageOrder(names: ["1", "2", "3"])
        order.reconcile(with: ["1", "3"], mode: .dynamic)
        #expect(order.names == ["1", "3"])
        #expect(order.name(atPosition: 2) == "3")
        #expect(order.position(of: "3") == 2)
        #expect(order.name(atPosition: 3) == nil)
    }

    @Test func fixedSortsNumerically() {
        var order = StageOrder(names: ["3", "1"])
        order.reconcile(with: ["10", "2", "1"], mode: .fixed)
        #expect(order.names == ["1", "2", "10"])
    }

    @Test func neighborWrapsAround() {
        let order = StageOrder(names: ["1", "4", "2"])
        #expect(order.neighbor(of: "2", offset: 1) == "1")
        #expect(order.neighbor(of: "1", offset: -1) == "2")
        #expect(order.neighbor(of: "4", offset: 1) == "2")
        #expect(order.neighbor(of: "unknown", offset: 1) == "1")
        #expect(StageOrder().neighbor(of: "1", offset: 1) == nil)
    }

    @Test func nextFreeNameSkipsUsed() {
        #expect(StageOrder.nextFreeName(excluding: []) == "1")
        #expect(StageOrder.nextFreeName(excluding: ["1", "2", "4"]) == "3")
    }
}

@Suite struct ManagedConfigTests {
    let sample = """
    a = 1
    # >>> AeroStage: gaps (managed) >>>
    alt
    # <<< AeroStage: gaps <<<
    [mode.main.binding]
        # >>> AeroStage: stages (managed) >>>
        x = 'y'
        # <<< AeroStage: stages <<<
        ctrl-alt-h = 'focus left'
    """

    @Test func replacesOnlyBetweenMarkers() throws {
        let result = try #require(ManagedConfig.replacingBlock("gaps", in: sample, with: ["new1", "new2"]))
        #expect(result.contains("a = 1\n# >>> AeroStage: gaps (managed) >>>\nnew1\nnew2\n# <<< AeroStage: gaps <<<"))
        #expect(result.contains("x = 'y'"))
        #expect(!result.contains("\nalt\n"))
    }

    @Test func missingMarkersReturnNil() {
        #expect(ManagedConfig.replacingBlock("gaps", in: "a = 1", with: []) == nil)
    }

    @Test func gapsReserveSidebarOnlyOnItsMonitorAndSide() {
        let body = ManagedConfig.gapsBody(.init(inner: 8, outer: 8, sidebarMonitor: "DELL U4025QW", side: .right, sidebarGap: 200))
        #expect(body.contains("gaps.outer.right =      [{ monitor.'DELL U4025QW' = 200 }, 8]"))
        #expect(body.contains("gaps.outer.left =       8"))
    }

    @Test func gapsWithoutSidebarAreUniform() {
        let body = ManagedConfig.gapsBody(.init(inner: 4, outer: 6, sidebarMonitor: nil, side: .left, sidebarGap: 200))
        #expect(body.contains("gaps.outer.left =       6"))
        #expect(body.contains("gaps.inner.vertical =   4"))
    }

    @Test func monitorPatternIsEscaped() {
        #expect(ManagedConfig.monitorPattern("LG (27)") == #"LG \(27\)"#)
        #expect(ManagedConfig.monitorPattern("Bob's TV") == "Bob.s TV")
    }

    @Test func dynamicBindingsCallCli() {
        let body = ManagedConfig.stagesBody(.init(mode: .dynamic, modifier: "ctrl-alt", maxStages: 5, cliPath: "/x/aerostage"))
        #expect(body.contains(#"    ctrl-alt-5 = 'exec-and-forget "/x/aerostage" focus 5'"#))
        #expect(body.contains(#"    ctrl-alt-shift-1 = 'exec-and-forget "/x/aerostage" move 1'"#))
        #expect(!body.contains { $0.contains("ctrl-alt-6") })
        #expect(body.contains(#"    alt-tab = 'exec-and-forget "/x/aerostage" next'"#))
    }

    @Test func fixedBindingsUseAeroSpace() {
        let body = ManagedConfig.stagesBody(.init(mode: .fixed, modifier: "ctrl-alt", maxStages: 7, cliPath: "/x/aerostage"))
        #expect(body.contains("    ctrl-alt-7 = 'workspace 7'"))
        #expect(body.contains("    ctrl-alt-shift-7 = 'move-node-to-workspace 7'"))
    }

    @Test func templateHasBothBlocks() {
        #expect(ManagedConfig.replacingBlock("gaps", in: DefaultConfig.template, with: []) != nil)
        #expect(ManagedConfig.replacingBlock("stages", in: DefaultConfig.template, with: []) != nil)
    }
}

@Suite struct DecodingTests {
    @Test func decodesSubscribeEvents() throws {
        let event = try #require(AeroEvent.decode(line: Data(#"{"_event":"focused-workspace-changed","prevWorkspace":"1","workspace":"2"}"#.utf8)))
        #expect(event.kind == .focusedWorkspaceChanged)
        #expect(event.workspace == "2")
        #expect(event.prevWorkspace == "1")
        #expect(AeroEvent.decode(line: Data("not json".utf8)) == nil)
    }

    @Test func decodesWindowList() throws {
        let json = """
        [{"app-bundle-id":"org.mozilla.firefox","app-name":"Firefox","monitor-id":1,"window-id":15698,"window-title":"Start","workspace":"1"}]
        """
        let windows = try JSONDecoder().decode([AeroWindow].self, from: Data(json.utf8))
        #expect(windows.first?.appBundleId == "org.mozilla.firefox")
        #expect(windows.first?.monitorId == 1)
    }

    @Test func decodesMonitorList() throws {
        let json = #"[{"monitor-appkit-nsscreen-screens-id":1,"monitor-id":1,"monitor-name":"DELL U4025QW"}]"#
        let monitors = try JSONDecoder().decode([AeroMonitor].self, from: Data(json.utf8))
        #expect(monitors == [AeroMonitor(monitorId: 1, name: "DELL U4025QW", nsScreenIndex: 1)])
    }

    @Test func socketAddressRejectsLongPaths() {
        #expect(throws: IPCError.self) { try IPC.makeAddress(String(repeating: "x", count: 200)) }
    }
}
