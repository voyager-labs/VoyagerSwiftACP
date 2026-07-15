import VoyagerEntitiesAi

func aiChatEventSessionID(_ event: AiChatEvent) -> AiChatSessionID? {
    switch event {
    case let .started(context), let .delta(context, _), let .failed(context, _):
        context.sessionID
    case let .final(response):
        response.context.sessionID
    }
}

func aiChatEventIsTerminal(_ event: AiChatEvent) -> Bool {
    switch event {
    case .final, .failed: true
    case .started, .delta: false
    }
}
