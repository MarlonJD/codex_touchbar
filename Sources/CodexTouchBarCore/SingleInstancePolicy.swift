public enum SingleInstancePolicy {
    public static func shouldTerminate(currentPID: Int32, runningPIDs: [Int32]) -> Bool {
        runningPIDs.contains { $0 < currentPID }
    }
}
