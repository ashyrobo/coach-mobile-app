import Foundation

protocol PermissionServicing {
    func requestMicrophonePermission() async -> Bool
    func requestSpeechPermission() async -> Bool
}
