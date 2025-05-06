/// swfit-api-examples/SherpaOnnx.swift
/// Copyright (c)  2023  Xiaomi Corporation

import Foundation  // For NSString
import SherpaOnnxC

/// Convert a String from swift to a `const char*` so that we can pass it to
/// the C language.
///
/// - Parameters:
///   - s: The String to convert.
/// - Returns: A pointer that can be passed to C as `const char*`

func toCPointer(_ s: String) -> UnsafePointer<Int8>! {
  let cs = (s as NSString).utf8String
  return UnsafePointer<Int8>(cs)
}

/// Return an instance of SherpaOnnxOnlineTransducerModelConfig.
///
/// Please refer to
/// https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-transducer/index.html
/// to download the required `.onnx` files.
///
/// - Parameters:
///   - encoder: Path to encoder.onnx
///   - decoder: Path to decoder.onnx
///   - joiner: Path to joiner.onnx
///
/// - Returns: Return an instance of SherpaOnnxOnlineTransducerModelConfig
func sherpaOnnxOnlineTransducerModelConfig(
  encoder: String = "",
  decoder: String = "",
  joiner: String = ""
) -> SherpaOnnxOnlineTransducerModelConfig {
  return SherpaOnnxOnlineTransducerModelConfig(
    encoder: toCPointer(encoder),
    decoder: toCPointer(decoder),
    joiner: toCPointer(joiner)
  )
}

/// Return an instance of SherpaOnnxOnlineParaformerModelConfig.
///
/// Please refer to
/// https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-paraformer/index.html
/// to download the required `.onnx` files.
///
/// - Parameters:
///   - encoder: Path to encoder.onnx
///   - decoder: Path to decoder.onnx
///
/// - Returns: Return an instance of SherpaOnnxOnlineParaformerModelConfig
func sherpaOnnxOnlineParaformerModelConfig(
  encoder: String = "",
  decoder: String = ""
) -> SherpaOnnxOnlineParaformerModelConfig {
  return SherpaOnnxOnlineParaformerModelConfig(
    encoder: toCPointer(encoder),
    decoder: toCPointer(decoder)
  )
}

func sherpaOnnxOnlineZipformer2CtcModelConfig(
  model: String = ""
) -> SherpaOnnxOnlineZipformer2CtcModelConfig {
  return SherpaOnnxOnlineZipformer2CtcModelConfig(
    model: toCPointer(model)
  )
}

/// Return an instance of SherpaOnnxOnlineModelConfig.
///
/// Please refer to
/// https://k2-fsa.github.io/sherpa/onnx/pretrained_models/index.html
/// to download the required `.onnx` files.
///
/// - Parameters:
///   - tokens: Path to tokens.txt
///   - numThreads:  Number of threads to use for neural network computation.
///
/// - Returns: Return an instance of SherpaOnnxOnlineTransducerModelConfig
func sherpaOnnxOnlineModelConfig(
  tokens: String,
  transducer: SherpaOnnxOnlineTransducerModelConfig = sherpaOnnxOnlineTransducerModelConfig(),
  paraformer: SherpaOnnxOnlineParaformerModelConfig = sherpaOnnxOnlineParaformerModelConfig(),
  zipformer2Ctc: SherpaOnnxOnlineZipformer2CtcModelConfig =
    sherpaOnnxOnlineZipformer2CtcModelConfig(),
  numThreads: Int = 1,
  provider: String = "cpu",
  debug: Int = 0,
  modelType: String = "",
  modelingUnit: String = "cjkchar",
  bpeVocab: String = "",
  tokensBuf: String = "",
  tokensBufSize: Int = 0
) -> SherpaOnnxOnlineModelConfig {
  return SherpaOnnxOnlineModelConfig(
    transducer: transducer,
    paraformer: paraformer,
    zipformer2_ctc: zipformer2Ctc,
    tokens: toCPointer(tokens),
    num_threads: Int32(numThreads),
    provider: toCPointer(provider),
    debug: Int32(debug),
    model_type: toCPointer(modelType),
    modeling_unit: toCPointer(modelingUnit),
    bpe_vocab: toCPointer(bpeVocab),
    tokens_buf: toCPointer(tokensBuf),
    tokens_buf_size: Int32(tokensBufSize)
  )
}

func sherpaOnnxFeatureConfig(
  sampleRate: Int = 16000,
  featureDim: Int = 80
) -> SherpaOnnxFeatureConfig {
  return SherpaOnnxFeatureConfig(
    sample_rate: Int32(sampleRate),
    feature_dim: Int32(featureDim))
}

/// Wrapper for recognition result.
///
/// Usage:
///
///  let result = recognizer.getResult()
///  print("text: \(result.text)")
///
class SherpaOnnxOnlineRecongitionResult {
  /// A pointer to the underlying counterpart in C
  let result: UnsafePointer<SherpaOnnxOnlineRecognizerResult>!

  /// Return the actual recognition result.
  /// For English models, it contains words separated by spaces.
  /// For Chinese models, it contains Chinese words.
  var text: String {
    return String(cString: result.pointee.text)
  }

  var count: Int32 {
    return result.pointee.count
  }

  var tokens: [String] {
    if let tokensPointer = result.pointee.tokens_arr {
      var tokens: [String] = []
      for index in 0..<count {
        if let tokenPointer = tokensPointer[Int(index)] {
          let token = String(cString: tokenPointer)
          tokens.append(token)
        }
      }
      return tokens
    } else {
      let tokens: [String] = []
      return tokens
    }
  }

  var timestamps: [Float] {
    if let p = result.pointee.timestamps {
      var timestamps: [Float] = []
      for index in 0..<count {
        timestamps.append(p[Int(index)])
      }
      return timestamps
    } else {
      let timestamps: [Float] = []
      return timestamps
    }
  }

  init(result: UnsafePointer<SherpaOnnxOnlineRecognizerResult>!) {
    self.result = result
  }

  deinit {
    if let result {
      SherpaOnnxDestroyOnlineRecognizerResult(result)
    }
  }
}

func sherpaOnnxOfflineLMConfig(
  model: String = "",
  scale: Float = 1.0
) -> SherpaOnnxOfflineLMConfig {
  return SherpaOnnxOfflineLMConfig(
    model: toCPointer(model),
    scale: scale
  )
}

class SherpaOnnxSpeechSegmentWrapper {
  let p: UnsafePointer<SherpaOnnxSpeechSegment>!

  init(p: UnsafePointer<SherpaOnnxSpeechSegment>!) {
    self.p = p
  }

  deinit {
    if let p {
      SherpaOnnxDestroySpeechSegment(p)
    }
  }

  var start: Int {
    return Int(p.pointee.start)
  }

  var n: Int {
    return Int(p.pointee.n)
  }

  var samples: [Float] {
    var samples: [Float] = []
    for index in 0..<n {
      samples.append(p.pointee.samples[Int(index)])
    }
    return samples
  }
}

class SherpaOnnxVoiceActivityDetectorWrapper {
  /// A pointer to the underlying counterpart in C
  let vad: OpaquePointer!

  init(config: UnsafePointer<SherpaOnnxVadModelConfig>!, buffer_size_in_seconds: Float) {
    vad = SherpaOnnxCreateVoiceActivityDetector(config, buffer_size_in_seconds)
  }

  deinit {
    if let vad {
      SherpaOnnxDestroyVoiceActivityDetector(vad)
    }
  }

  func acceptWaveform(samples: [Float]) {
    SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad, samples, Int32(samples.count))
  }

  func isEmpty() -> Bool {
    return SherpaOnnxVoiceActivityDetectorEmpty(vad) == 1
  }

  func isSpeechDetected() -> Bool {
    return SherpaOnnxVoiceActivityDetectorDetected(vad) == 1
  }

  func pop() {
    SherpaOnnxVoiceActivityDetectorPop(vad)
  }

  func clear() {
    SherpaOnnxVoiceActivityDetectorClear(vad)
  }

  func front() -> SherpaOnnxSpeechSegmentWrapper {
    let p: UnsafePointer<SherpaOnnxSpeechSegment>? = SherpaOnnxVoiceActivityDetectorFront(vad)
    return SherpaOnnxSpeechSegmentWrapper(p: p)
  }

  func reset() {
    SherpaOnnxVoiceActivityDetectorReset(vad)
  }

  func flush() {
    SherpaOnnxVoiceActivityDetectorFlush(vad)
  }
}

// offline tts
func sherpaOnnxOfflineTtsVitsModelConfig(
  model: String = "",
  lexicon: String = "",
  tokens: String = "",
  dataDir: String = "",
  noiseScale: Float = 0.667,
  noiseScaleW: Float = 0.8,
  lengthScale: Float = 1.0,
  dictDir: String = ""
) -> SherpaOnnxOfflineTtsVitsModelConfig {
  return SherpaOnnxOfflineTtsVitsModelConfig(
    model: toCPointer(model),
    lexicon: toCPointer(lexicon),
    tokens: toCPointer(tokens),
    data_dir: toCPointer(dataDir),
    noise_scale: noiseScale,
    noise_scale_w: noiseScaleW,
    length_scale: lengthScale,
    dict_dir: toCPointer(dictDir)
  )
}

func sherpaOnnxOfflineTtsMatchaModelConfig(
  acousticModel: String = "",
  vocoder: String = "",
  lexicon: String = "",
  tokens: String = "",
  dataDir: String = "",
  noiseScale: Float = 0.667,
  lengthScale: Float = 1.0,
  dictDir: String = ""
) -> SherpaOnnxOfflineTtsMatchaModelConfig {
  return SherpaOnnxOfflineTtsMatchaModelConfig(
    acoustic_model: toCPointer(acousticModel),
    vocoder: toCPointer(vocoder),
    lexicon: toCPointer(lexicon),
    tokens: toCPointer(tokens),
    data_dir: toCPointer(dataDir),
    noise_scale: noiseScale,
    length_scale: lengthScale,
    dict_dir: toCPointer(dictDir)
  )
}

func sherpaOnnxOfflineTtsKokoroModelConfig(
  model: String = "",
  voices: String = "",
  tokens: String = "",
  dataDir: String = "",
  lengthScale: Float = 1.0,
  dictDir: String = "",
  lexicon: String = ""
) -> SherpaOnnxOfflineTtsKokoroModelConfig {
  return SherpaOnnxOfflineTtsKokoroModelConfig(
    model: toCPointer(model),
    voices: toCPointer(voices),
    tokens: toCPointer(tokens),
    data_dir: toCPointer(dataDir),
    length_scale: lengthScale,
    dict_dir: toCPointer(dictDir),
    lexicon: toCPointer(lexicon)
  )
}

func sherpaOnnxOfflineTtsModelConfig(
  vits: SherpaOnnxOfflineTtsVitsModelConfig = sherpaOnnxOfflineTtsVitsModelConfig(),
  matcha: SherpaOnnxOfflineTtsMatchaModelConfig = sherpaOnnxOfflineTtsMatchaModelConfig(),
  kokoro: SherpaOnnxOfflineTtsKokoroModelConfig = sherpaOnnxOfflineTtsKokoroModelConfig(),
  numThreads: Int = 1,
  debug: Int = 0,
  provider: String = "cpu"
) -> SherpaOnnxOfflineTtsModelConfig {
  return SherpaOnnxOfflineTtsModelConfig(
    vits: vits,
    num_threads: Int32(numThreads),
    debug: Int32(debug),
    provider: toCPointer(provider),
    matcha: matcha,
    kokoro: kokoro
  )
}

func sherpaOnnxOfflineTtsConfig(
  model: SherpaOnnxOfflineTtsModelConfig,
  ruleFsts: String = "",
  ruleFars: String = "",
  maxNumSentences: Int = 1,
  silenceScale: Float = 0.2
) -> SherpaOnnxOfflineTtsConfig {
  return SherpaOnnxOfflineTtsConfig(
    model: model,
    rule_fsts: toCPointer(ruleFsts),
    max_num_sentences: Int32(maxNumSentences),
    rule_fars: toCPointer(ruleFars),
    silence_scale: silenceScale
  )
}

public class SherpaOnnxGeneratedAudioWrapper {
  /// A pointer to the underlying counterpart in C
  let audio: UnsafePointer<SherpaOnnxGeneratedAudio>!

  init(audio: UnsafePointer<SherpaOnnxGeneratedAudio>!) {
    self.audio = audio
  }

  deinit {
    if let audio {
      SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio)
    }
  }

  var n: Int32 {
    return audio.pointee.n
  }

  var sampleRate: Int32 {
    return audio.pointee.sample_rate
  }

  var samples: [Float] {
    if let p = audio.pointee.samples {
      var samples: [Float] = []
      for index in 0..<n {
        samples.append(p[Int(index)])
      }
      return samples
    } else {
      let samples: [Float] = []
      return samples
    }
  }

  func save(filename: String) -> Int32 {
    return SherpaOnnxWriteWave(audio.pointee.samples, n, sampleRate, toCPointer(filename))
  }
}

typealias TtsCallbackWithArg = (
  @convention(c) (
    UnsafePointer<Float>?,  // const float* samples
    Int32,  // int32_t n
    UnsafeMutableRawPointer?  // void *arg
  ) -> Int32
)?

class SherpaOnnxOfflineTtsWrapper {
  /// A pointer to the underlying counterpart in C
  let tts: OpaquePointer!

  /// Constructor taking a model config
  init(
    config: UnsafePointer<SherpaOnnxOfflineTtsConfig>!
  ) {
    tts = SherpaOnnxCreateOfflineTts(config)
  }

  deinit {
    if let tts {
      SherpaOnnxDestroyOfflineTts(tts)
    }
  }

  func generate(text: String, sid: Int = 0, speed: Float = 1.0) -> SherpaOnnxGeneratedAudioWrapper {
    let audio: UnsafePointer<SherpaOnnxGeneratedAudio>? = SherpaOnnxOfflineTtsGenerate(
      tts, toCPointer(text), Int32(sid), speed)

    return SherpaOnnxGeneratedAudioWrapper(audio: audio)
  }

  func generateWithCallbackWithArg(
    text: String, callback: TtsCallbackWithArg, arg: UnsafeMutableRawPointer, sid: Int = 0,
    speed: Float = 1.0
  ) -> SherpaOnnxGeneratedAudioWrapper {
    let audio: UnsafePointer<SherpaOnnxGeneratedAudio>? =
      SherpaOnnxOfflineTtsGenerateWithCallbackWithArg(
        tts, toCPointer(text), Int32(sid), speed, callback, arg)

    return SherpaOnnxGeneratedAudioWrapper(audio: audio)
  }
}

// spoken language identification

func sherpaOnnxSpokenLanguageIdentificationWhisperConfig(
  encoder: String,
  decoder: String,
  tailPaddings: Int = -1
) -> SherpaOnnxSpokenLanguageIdentificationWhisperConfig {
  return SherpaOnnxSpokenLanguageIdentificationWhisperConfig(
    encoder: toCPointer(encoder),
    decoder: toCPointer(decoder),
    tail_paddings: Int32(tailPaddings))
}

func sherpaOnnxSpokenLanguageIdentificationConfig(
  whisper: SherpaOnnxSpokenLanguageIdentificationWhisperConfig,
  numThreads: Int = 1,
  debug: Int = 0,
  provider: String = "cpu"
) -> SherpaOnnxSpokenLanguageIdentificationConfig {
  return SherpaOnnxSpokenLanguageIdentificationConfig(
    whisper: whisper,
    num_threads: Int32(numThreads),
    debug: Int32(debug),
    provider: toCPointer(provider))
}

class SherpaOnnxSpokenLanguageIdentificationResultWrapper {
  /// A pointer to the underlying counterpart in C
  let result: UnsafePointer<SherpaOnnxSpokenLanguageIdentificationResult>!

  /// Return the detected language.
  /// en for English
  /// zh for Chinese
  /// es for Spanish
  /// de for German
  /// etc.
  var lang: String {
    return String(cString: result.pointee.lang)
  }

  init(result: UnsafePointer<SherpaOnnxSpokenLanguageIdentificationResult>!) {
    self.result = result
  }

  deinit {
    if let result {
      SherpaOnnxDestroySpokenLanguageIdentificationResult(result)
    }
  }
}

class SherpaOnnxSpokenLanguageIdentificationWrapper {
  /// A pointer to the underlying counterpart in C
  let slid: OpaquePointer!

  init(
    config: UnsafePointer<SherpaOnnxSpokenLanguageIdentificationConfig>!
  ) {
    slid = SherpaOnnxCreateSpokenLanguageIdentification(config)
  }

  deinit {
    if let slid {
      SherpaOnnxDestroySpokenLanguageIdentification(slid)
    }
  }

  func decode(samples: [Float], sampleRate: Int = 16000)
    -> SherpaOnnxSpokenLanguageIdentificationResultWrapper
  {
    let stream: OpaquePointer! = SherpaOnnxSpokenLanguageIdentificationCreateOfflineStream(slid)
    SherpaOnnxAcceptWaveformOffline(stream, Int32(sampleRate), samples, Int32(samples.count))

    let result: UnsafePointer<SherpaOnnxSpokenLanguageIdentificationResult>? =
      SherpaOnnxSpokenLanguageIdentificationCompute(
        slid,
        stream)

    SherpaOnnxDestroyOfflineStream(stream)
    return SherpaOnnxSpokenLanguageIdentificationResultWrapper(result: result)
  }
}

// keyword spotting

class SherpaOnnxKeywordResultWrapper {
  /// A pointer to the underlying counterpart in C
  let result: UnsafePointer<SherpaOnnxKeywordResult>!

  var keyword: String {
    return String(cString: result.pointee.keyword)
  }

  var count: Int32 {
    return result.pointee.count
  }

  var tokens: [String] {
    if let tokensPointer = result.pointee.tokens_arr {
      var tokens: [String] = []
      for index in 0..<count {
        if let tokenPointer = tokensPointer[Int(index)] {
          let token = String(cString: tokenPointer)
          tokens.append(token)
        }
      }
      return tokens
    } else {
      let tokens: [String] = []
      return tokens
    }
  }

  init(result: UnsafePointer<SherpaOnnxKeywordResult>!) {
    self.result = result
  }

  deinit {
    if let result {
      SherpaOnnxDestroyKeywordResult(result)
    }
  }
}

func sherpaOnnxKeywordSpotterConfig(
  featConfig: SherpaOnnxFeatureConfig,
  modelConfig: SherpaOnnxOnlineModelConfig,
  keywordsFile: String,
  maxActivePaths: Int = 4,
  numTrailingBlanks: Int = 1,
  keywordsScore: Float = 1.0,
  keywordsThreshold: Float = 0.25,
  keywordsBuf: String = "",
  keywordsBufSize: Int = 0
) -> SherpaOnnxKeywordSpotterConfig {
  return SherpaOnnxKeywordSpotterConfig(
    feat_config: featConfig,
    model_config: modelConfig,
    max_active_paths: Int32(maxActivePaths),
    num_trailing_blanks: Int32(numTrailingBlanks),
    keywords_score: keywordsScore,
    keywords_threshold: keywordsThreshold,
    keywords_file: toCPointer(keywordsFile),
    keywords_buf: toCPointer(keywordsBuf),
    keywords_buf_size: Int32(keywordsBufSize)
  )
}
