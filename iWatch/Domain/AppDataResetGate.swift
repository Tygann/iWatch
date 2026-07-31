actor AppDataResetGate {
    private var resetInProgress = false

    func beginReset() {
        resetInProgress = true
    }

    func endReset() {
        resetInProgress = false
    }

    func allowsLibraryWork() -> Bool {
        !resetInProgress
    }
}
