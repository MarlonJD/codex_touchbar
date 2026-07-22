import CodexTouchBarCore
import Testing

@Test func keepsTheOnlyRunningInstance() {
    #expect(!SingleInstancePolicy.shouldTerminate(currentPID: 42, runningPIDs: [42]))
}

@Test func rejectsASecondRunningInstance() {
    #expect(SingleInstancePolicy.shouldTerminate(currentPID: 84, runningPIDs: [42, 84]))
}

@Test func keepsTheOldestInstanceWhenTwoAreVisible() {
    #expect(!SingleInstancePolicy.shouldTerminate(currentPID: 42, runningPIDs: [84, 42]))
}
