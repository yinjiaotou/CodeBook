public enum MasterPasswordPolicy {
    public static let minimumLength = 12

    public static func isValid(_ password: String) -> Bool {
        password.count >= minimumLength
    }
}
