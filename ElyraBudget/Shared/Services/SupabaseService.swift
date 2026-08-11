import Foundation
import Supabase

enum SupabaseService {
    static let client: SupabaseClient = {
        guard let url = URL(string: "https://tbsskmbiwxrocjtkqtil.supabase.co") else {
            preconditionFailure("Die Supabase-Projekt-URL ist ungültig.")
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: "sb_publishable_RM1kfHZnIwShuBlqF_Fi7A_J7gn8eud"
        )
    }()
}
