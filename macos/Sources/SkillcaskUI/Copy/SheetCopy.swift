/// The words every sheet shares (ReviewUpdate, AddSkill, Adopt-States boards): the footer's Cancel. A sheet's own
/// words live in its feature's copy file (`ReviewUpdateCopy`, `AddSkillCopy`, `AdoptCopy`, `RemoveCopy`).
public enum SheetCopy {
    /// The footer's cancel button: stops the run while one is in flight, else closes the sheet.
    public static let cancel = "Cancel"
    /// Why a sheet's command did not start: the app runs one command at a time (no board source).
    public static let anotherRunInFlight = "Another command is still running. Try again when it has finished."
}
