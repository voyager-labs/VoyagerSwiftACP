import VoyagerEntitiesAi

func aiChatEventSessionID(_ event: AiChatEvent) -> AiChatSessionID? {
    switch event {
    case let .requestPrepared(context),
         let .started(context),
         let .delta(context, _),
         let .status(context, _),
         let .failed(context, _):
        context.sessionID
    case let .final(response):
        response.context.sessionID
    }
}

func aiChatEventIsTerminal(_ event: AiChatEvent) -> Bool {
    switch event {
    case .final, .failed: true
    case .requestPrepared, .started, .delta, .status: false
    }
}
