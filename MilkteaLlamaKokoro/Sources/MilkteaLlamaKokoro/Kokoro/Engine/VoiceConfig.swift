import Foundation

/// Defines all available TTS voices with their IDs and names.
public enum VoiceConfig: Int, CaseIterable {
    case afAlloy = 0
    case afAoede = 1
    case afBella = 2
    case afHeart = 3
    case afJessica = 4
    case afKore = 5
    case afNicole = 6
    case afNova = 7
    case afRiver = 8
    case afSarah = 9
    case afSky = 10
    case amAdam = 11
    case amEcho = 12
    case amEric = 13
    case amFenrir = 14
    case amLiam = 15
    case amMichael = 16
    case amOnyx = 17
    case amPuck = 18
    case amSanta = 19
    case bfAlice = 20
    case bfEmma = 21
    case bfIsabella = 22
    case bfLily = 23
    case bmDaniel = 24
    case bmFable = 25
    case bmGeorge = 26
    case bmLewis = 27
    case efDora = 28
    case emAlex = 29
    case ffSiwis = 30
    case hfAlpha = 31
    case hfBeta = 32
    case hmOmega = 33
    case hmPsi = 34
    case ifSara = 35
    case imNicola = 36
    case jfAlpha = 37
    case jfGongitsune = 38
    case jfNezumi = 39
    case jfTebukuro = 40
    case jmKumo = 41
    case pfDora = 42
    case pmAlex = 43
    case pmSanta = 44
    case zfXiaobei = 45
    case zfXiaoni = 46
    case zfXiaoxiao = 47
    case zfXiaoyi = 48
    case zmYunjian = 49
    case zmYunxi = 50
    case zmYunxia = 51
    case zmYunyang = 52
}

public extension VoiceConfig {
    /// The string name of the voice used by the TTS engine.
    var voiceName: String {
        switch self {
        case .afAlloy:      return "af_alloy"
        case .afAoede:      return "af_aoede"
        case .afBella:      return "af_bella"
        case .afHeart:      return "af_heart"
        case .afJessica:    return "af_jessica"
        case .afKore:       return "af_kore"
        case .afNicole:     return "af_nicole"
        case .afNova:       return "af_nova"
        case .afRiver:      return "af_river"
        case .afSarah:      return "af_sarah"
        case .afSky:        return "af_sky"
        case .amAdam:       return "am_adam"
        case .amEcho:       return "am_echo"
        case .amEric:       return "am_eric"
        case .amFenrir:     return "am_fenrir"
        case .amLiam:       return "am_liam"
        case .amMichael:    return "am_michael"
        case .amOnyx:       return "am_onyx"
        case .amPuck:       return "am_puck"
        case .amSanta:      return "am_santa"
        case .bfAlice:      return "bf_alice"
        case .bfEmma:       return "bf_emma"
        case .bfIsabella:   return "bf_isabella"
        case .bfLily:       return "bf_lily"
        case .bmDaniel:     return "bm_daniel"
        case .bmFable:      return "bm_fable"
        case .bmGeorge:     return "bm_george"
        case .bmLewis:      return "bm_lewis"
        case .efDora:       return "ef_dora"
        case .emAlex:       return "em_alex"
        case .ffSiwis:      return "ff_siwis"
        case .hfAlpha:      return "hf_alpha"
        case .hfBeta:       return "hf_beta"
        case .hmOmega:      return "hm_omega"
        case .hmPsi:        return "hm_psi"
        case .ifSara:       return "if_sara"
        case .imNicola:     return "im_nicola"
        case .jfAlpha:      return "jf_alpha"
        case .jfGongitsune: return "jf_gongitsune"
        case .jfNezumi:     return "jf_nezumi"
        case .jfTebukuro:   return "jf_tebukuro"
        case .jmKumo:       return "jm_kumo"
        case .pfDora:       return "pf_dora"
        case .pmAlex:       return "pm_alex"
        case .pmSanta:      return "pm_santa"
        case .zfXiaobei:    return "zf_xiaobei"
        case .zfXiaoni:     return "zf_xiaoni"
        case .zfXiaoxiao:   return "zf_xiaoxiao"
        case .zfXiaoyi:     return "zf_xiaoyi"
        case .zmYunjian:    return "zm_yunjian"
        case .zmYunxi:      return "zm_yunxi"
        case .zmYunxia:     return "zm_yunxia"
        case .zmYunyang:    return "zm_yunyang"
        }
    }

    /// A human‐friendly display name for UI, with special agent overrides.
    var displayName: String {
        switch self {
        case .afBella:      return "Annarky"
        case .afHeart:      return "M1lkt3a"
        case .bmGeorge:     return "Generic"
        case .amMichael:    return "Artist"
        case .bmFable:      return "Monster"
        default:
            // Drop the language/gender prefix and capitalize
            let part = voiceName.split(separator: "_").last.map(String.init) ?? voiceName
            return part.capitalized
        }
    }

    /// Determine which lexicon file to use based on voice ID.
    static func getLexiconFileForId(_ id: Int) -> String {
        switch id {
        case 0...19:  return "lexicon-gb-en.txt"
        case 20...27: return "lexicon-gb-en.txt"
        case 45...52: return "lexicon-us-en.txt"
        default:      return "lexicon-us-en.txt"
        }
    }
} 
