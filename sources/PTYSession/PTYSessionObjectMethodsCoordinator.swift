//
//  PTYSessionObjectMethodsCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m (Wave 3) to isolate iTermObject built-in
//  method registration and dispatch.
//

import Foundation

enum PTYSessionAnnotationRangeValidator {
    static func isValid(startX: Int,
                        startY: Int,
                        endX: Int,
                        endY: Int,
                        maxY: Int64) -> Bool {
        if startY > endY || startY < 0 || Int64(startY) > maxY || endY < 0 || Int64(endY) > maxY {
            return false
        }
        if startY == endY && startX > endX {
            return false
        }
        return true
    }
}

enum PTYSessionObjectMethodsPolicy {
    static func invalidAnnotationRangeError() -> NSError {
        return NSError(domain: "com.iterm2.add-annotation-command",
                       code: 0,
                       userInfo: [NSLocalizedDescriptionKey: "Invalid range"])
    }

    static func notTmuxSessionError() -> NSError {
        return NSError(domain: "com.iterm2.tmux-command",
                       code: 0,
                       userInfo: [NSLocalizedDescriptionKey: "Not a tmux integration session"])
    }

    static func tmuxCommandFailedError() -> NSError {
        return NSError(domain: "com.iterm2.tmux-command",
                       code: 1,
                       userInfo: [NSLocalizedDescriptionKey: "tmux error"])
    }

    static func timeOffsetPayload(offset: TimeInterval, timeZone: String?) -> [String: Any] {
        return [
            "offset": offset,
            "tz": timeZone ?? ""
        ]
    }
}

@objc final class PTYSessionObjectMethodsCoordinator: NSObject, iTermObject {
    private weak var session: PTYSession?
    private var methods: iTermBuiltInFunctions?

    @objc(initWithSession:)
    init(session: PTYSession) {
        self.session = session
        super.init()
    }

    @objc func objectMethodRegistry() -> iTermBuiltInFunctions? {
        if let methods {
            return methods
        }
        let registry = iTermBuiltInFunctions()
        let context: iTermVariablesSuggestionContext = .session

        let registered: [(name: String,
                          types: [String: AnyClass],
                          optionalArguments: Set<String>,
                          placeholder: String?,
                          selector: Selector)] = [
            ("set_name",
             ["name": NSString.self],
             [],
             "[set_name]",
             #selector(setName(completion:name:))),
            ("run_tmux_command",
             ["command": NSString.self],
             [],
             "[run_tmux_command]",
             #selector(sendTmuxCommand(completion:command:))),
            ("set_status_bar_component_unread_count",
             ["identifier": NSString.self, "count": NSNumber.self],
             [],
             "[set_status_bar_component_unread_count]",
             #selector(setStatusBarComponentUnreadCount(completion:identifier:count:))),
            ("stop_coprocess",
             [:],
             [],
             "[stop_coprocess]",
             #selector(stopCoprocess(completion:))),
            ("get_coprocess",
             [:],
             [],
             nil,
             #selector(getCoprocess(completion:))),
            ("run_coprocess",
             ["commandLine": NSString.self, "mute": NSNumber.self],
             ["mute"],
             "[run_coprocess]",
             #selector(runCoprocess(completion:commandLine:mute:))),
            ("add_annotation",
             ["startX": NSNumber.self,
              "startY": NSNumber.self,
              "endX": NSNumber.self,
              "endY": NSNumber.self,
              "text": NSString.self],
             [],
             "[add_annotation]",
             #selector(addAnnotation(completion:startX:startY:endX:endY:text:))),
            ("get_time_offset",
             [:],
             [],
             nil,
             #selector(fetchTimeOffset(completion:)))
        ]

        for entry in registered {
            let method = iTermBuiltInMethod(name: entry.name,
                                            defaultValues: [:],
                                            types: entry.types,
                                            optionalArguments: entry.optionalArguments,
                                            context: context,
                                            sideEffectsPlaceholder: entry.placeholder,
                                            target: self,
                                            action: entry.selector)
            registry.register(method, namespace: "iterm2")
        }
        methods = registry
        return registry
    }

    @objc func objectScope() -> iTermVariableScope? {
        return session?.genericScope
    }

    // MARK: - Built-in Actions

    @objc(stopCoprocessWithCompletion:)
    func stopCoprocess(completion: @escaping (Any?, NSError?) -> Void) {
        guard let session else {
            completion(NSNumber(value: false), nil)
            return
        }
        if !session.hasCoprocess {
            completion(NSNumber(value: false), nil)
            return
        }
        session.stopCoprocess()
        completion(NSNumber(value: true), nil)
    }

    @objc(getCoprocessWithCompletion:)
    func getCoprocess(completion: @escaping (Any?, NSError?) -> Void) {
        completion(session?.shell.coprocess?.command, nil)
    }

    @objc(runCoprocessWithCompletion:commandLine:mute:)
    func runCoprocess(completion: @escaping (Any?, NSError?) -> Void,
                      commandLine command: String,
                      mute muteNumber: NSNumber?) {
        guard let session else {
            completion(NSNumber(value: false), nil)
            return
        }
        let mute = muteNumber?.boolValue ?? false
        if session.hasCoprocess {
            completion(NSNumber(value: false), nil)
            return
        }
        session.launchCoprocess(withCommand: command, mute: mute)
        completion(NSNumber(value: true), nil)
    }

    @objc(addAnnotationWithCompletion:startX:startY:endX:endY:text:)
    func addAnnotation(completion: @escaping (Any?, NSError?) -> Void,
                       startX startXNumber: NSNumber,
                       startY startYNumber: NSNumber,
                       endX endXNumber: NSNumber,
                       endY endYNumber: NSNumber,
                       text: String) {
        guard let session else {
            completion(nil, PTYSessionObjectMethodsPolicy.invalidAnnotationRangeError())
            return
        }
        let maxY = session.screen.totalScrollbackOverflow() + Int64(session.screen.numberOfLines())
        guard PTYSessionAnnotationRangeValidator.isValid(startX: startXNumber.intValue,
                                                         startY: startYNumber.intValue,
                                                         endX: endXNumber.intValue,
                                                         endY: endYNumber.intValue,
                                                         maxY: maxY) else {
            completion(nil, PTYSessionObjectMethodsPolicy.invalidAnnotationRangeError())
            return
        }
        let range = VT100GridAbsCoordRangeMake(startXNumber.int32Value,
                                               startYNumber.int64Value,
                                               endXNumber.int32Value,
                                               endYNumber.int64Value)
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.addNote(withText: text, inAbsoluteRange: range)
        })
        completion(nil, nil)
    }

    @objc(fetchTimeOffsetWithCompletion:)
    func fetchTimeOffset(completion: @escaping (Any?, NSError?) -> Void) {
        guard let session else {
            completion(PTYSessionObjectMethodsPolicy.timeOffsetPayload(offset: 0, timeZone: TimeZone.current.abbreviation()), nil)
            return
        }
        guard let conductor = session.conductor else {
            let tz = TimeZone.current.abbreviation()
            completion(PTYSessionObjectMethodsPolicy.timeOffsetPayload(offset: 0, timeZone: tz), nil)
            return
        }
        MainActor.assumeIsolated {
            conductor.fetchTimeOffset { offset, tz, error in
                if let error {
                    completion(nil, error)
                } else {
                    completion(PTYSessionObjectMethodsPolicy.timeOffsetPayload(offset: offset, timeZone: tz), nil)
                }
            }
        }
    }

    @objc(setStatusBarComponentUnreadCountWithCompletion:identifier:count:)
    func setStatusBarComponentUnreadCount(completion: @escaping (Any?, NSError?) -> Void,
                                          identifier: String,
                                          count: NSNumber) {
        guard let session else {
            completion(nil, nil)
            return
        }
        iTermStatusBarUnreadCountController.sharedInstance().setUnreadCountForComponentWithIdentifier(
            identifier,
            count: count.intValue,
            sessionID: session.guid
        )
        completion(nil, nil)
    }

    @objc(sendTmuxCommandWithCompletion:command:)
    func sendTmuxCommand(completion: @escaping (Any?, NSError?) -> Void,
                         command: String) {
        guard let session,
              session.tmuxMode != TMUX_NONE,
              let tmuxController = session.tmuxController else {
            completion(nil, PTYSessionObjectMethodsPolicy.notTmuxSessionError())
            return
        }
        tmuxController.gateway.sendCommand(
            command,
            responseTarget: self,
            responseSelector: #selector(sendTmuxCommandMethodDidComplete(_:completion:)),
            responseObject: completion,
            flags: kTmuxGatewayCommandOptions.tmuxGatewayCommandShouldTolerateErrors.rawValue
        )
    }

    @objc(sendTmuxCommandMethodDidComplete:completion:)
    func sendTmuxCommandMethodDidComplete(_ result: String?,
                                          completion: (Any?, NSError?) -> Void) {
        if let result {
            completion(result, nil)
            return
        }
        completion(nil, PTYSessionObjectMethodsPolicy.tmuxCommandFailedError())
    }

    @objc(setNameWithCompletion:name:)
    func setName(completion: @escaping (Any?, NSError?) -> Void,
                 name: String?) {
        session?.setSessionSpecificProfileValues([KEY_NAME: name ?? ""])
        completion(nil, nil)
    }
}
