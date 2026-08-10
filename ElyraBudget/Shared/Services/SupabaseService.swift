import Foundation
import Supabase

enum SupabaseService {
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://tbsskmbiwxrocjtkqtil.supabase.co")!,
        supabaseKey: "sb_publishable_RM1kfHZnIwShuBlqF_Fi7A_J7gn8eud"
    )
}
