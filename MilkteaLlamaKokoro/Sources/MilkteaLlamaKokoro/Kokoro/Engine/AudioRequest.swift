struct AudioRequest {
    let text: String
    let onSuccess: (SherpaOnnxGeneratedAudioWrapper) -> Void
    let onError: (Error) -> Void
}
