//
//  iTermScrollWheelStateMachine.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/20.
//

import AppKit

@objc(iTermScrollWheelStateMachine)
final class iTermScrollWheelStateMachine: NSObject {
    @objc private(set) var state: iTermScrollWheelStateMachineState = .ground

    private typealias Transition = (from: iTermScrollWheelStateMachineState,
                                   phase: NSEvent.Phase,
                                   momentum: NSEvent.Phase,
                                   to: iTermScrollWheelStateMachineState)

    // Order matters: NSEvent phases are flags, and the first matching transition wins.
    private static let transitions: [Transition] = [
        (.ground, .began, [], .startDrag),
        (.ground, .mayBegin, [], .touchAndHold),
        (.ground, [], .changed, .ground),
        (.ground, [], .began, .ground),
        (.ground, [], .ended, .ground),
        (.ground, .changed, [], .ground),
        (.ground, .ended, [], .ground),
        (.startDrag, .changed, [], .drag),
        (.startDrag, .ended, [], .ground),
        (.drag, .ended, [], .ground),
        (.drag, .changed, [], .drag),
        (.drag, [], .changed, .ground),
        (.touchAndHold, .began, [], .startDrag),
        (.touchAndHold, .cancelled, [], .ground)
    ]

    override var description: String {
        "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque()) state=\(stateName)>"
    }

    @objc(handleEvent:) func handleEvent(_ event: NSEvent) {
        if !handle(phase: event.phase, momentumPhase: event.momentumPhase) {
            DLog("Ignore unexpected event in state \(stateName): \(Self.shortEventPhasesString(event))")
        }
    }

    // Keep phase processing independent of NSEvent construction and the tracking loop.
    @discardableResult
    func handle(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase) -> Bool {
        guard let transition = Self.transitions.first(where: {
            $0.from == state &&
            Self.matches(phase, expected: $0.phase) &&
            Self.matches(momentumPhase, expected: $0.momentum)
        }) else {
            return false
        }
        DLog("setState \(stateName) -> \(Self.name(for: transition.to))")
        state = transition.to
        return true
    }

    private static func matches(_ phase: NSEvent.Phase, expected: NSEvent.Phase) -> Bool {
        // An empty phase must match exactly; it is not a wildcard.
        expected.isEmpty ? phase.isEmpty : !phase.intersection(expected).isEmpty
    }

    private var stateName: String { Self.name(for: state) }

    private static func name(for state: iTermScrollWheelStateMachineState) -> String {
        switch state {
        case .ground: return "Ground"
        case .startDrag: return "StartDrag"
        case .drag: return "Drag"
        case .touchAndHold: return "TouchAndHold"
        @unknown default: return String(state.rawValue)
        }
    }

    @objc(shortEventPhasesString:)
    static func shortEventPhasesString(_ event: NSEvent) -> String {
        let delta = String(format: "%f", event.scrollingDeltaX)
        return "<NSEvent: \(Unmanaged.passUnretained(event).toOpaque()) " +
            "phase=\(phaseName(event.phase)), momentumPhase=\(phaseName(event.momentumPhase)), " +
            "scrollingDeltaX=\(delta)>"
    }

    private static func phaseName(_ phase: NSEvent.Phase) -> String {
        let names: [(NSEvent.Phase, String)] = [
            (.began, "Began"), (.ended, "Ended"), (.changed, "Changed"),
            (.cancelled, "Cancelled"), (.stationary, "Stationary"), (.mayBegin, "MayBegin")
        ]
        let matched = names.compactMap { phase.contains($0.0) ? $0.1 : nil }
        return matched.isEmpty ? "None" : matched.joined(separator: "|")
    }
}
