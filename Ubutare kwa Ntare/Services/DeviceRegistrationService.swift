import Foundation

enum DeviceRegistrationStatus {
    case success, unauthorized, failed
}

final class DeviceRegistrationService {
    static let shared = DeviceRegistrationService()

    func registerAfterLogin(token: String, deviceToken: String) async -> DeviceRegistrationStatus {
        guard !deviceToken.isEmpty else { return .failed }
        let request = RegisterUserDeviceRequest(
            deviceId: AuthSessionManager.shared.deviceId(),
            deviceType: AppConstants.deviceTypeIOS,
            deviceToken: deviceToken
        )
        do {
            let response = try await APIClient.shared.registerUserDevice(token: token, request: request)
            return response.status ? .success : .failed
        } catch APIError.unauthorized {
            return .unauthorized
        } catch {
            return .failed
        }
    }
}
