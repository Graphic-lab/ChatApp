import Foundation

/// Maps backend error codes (raised in supabase/migrations) to Dutch user messages.
enum AppError {
    static let messages: [String: String] = [
        "not_invited": "Dit e-mailadres is nog niet uitgenodigd.",
        "owner_protected": "De eigenaar van de app kan niet verwijderd of geblokkeerd worden.",
        "owner_only": "Alleen de eigenaar kan dit doen.",
        "admin_only": "Alleen een groepsbeheerder kan dit doen.",
        "blocked": "Dit contact is geblokkeerd.",
        "user_not_found": "Geen gebruiker gevonden met dit e-mailadres.",
        "invalid_user": "Deze gebruiker is niet beschikbaar.",
        "title_required": "Geef de groep een naam.",
        "not_allowed": "Dit is niet toegestaan.",
        "row-level security": "Dit is niet toegestaan.",
    ]

    static func message(for error: Error) -> String {
        message(forText: String(describing: error) + " " + error.localizedDescription)
    }

    static func message(forText text: String) -> String {
        for (code, message) in messages where text.contains(code) {
            return message
        }
        return "Er ging iets mis. Probeer opnieuw."
    }
}
