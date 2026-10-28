/// The sections of the skill detail, in the order the Main board's "Detail sections" tablist draws them.
public enum DetailTab: String, CaseIterable, Hashable, Sendable {
    case overview
    case contents
    case security
    case versions
}
