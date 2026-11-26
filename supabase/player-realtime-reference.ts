// Kingdom in Chaos DTP — client-side Supabase Realtime reference (v14)
// For a web/TypeScript client using supabase-js v2. This is NOT automatically linked
// into the Android Java/native game. The native game needs an equivalent WebSocket
// subscription plus code that applies economy values to its actual save/game state.
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

export type EconomyState = {
  coins: string | number;
  crystals: string | number;
  goblin_coins: string | number;
  hero_xp: string | number;
  hero_level: number;
  player_xp: string | number;
  player_level: number;
  energy: string | number;
  stamina: string | number;
  honor_points: string | number;
  arena_tokens: string | number;
  skill_points: string | number;
  extra_stats: Record<string, unknown>;
  updated_at: string;
};

export function subscribeToMyEconomy(
  supabase: SupabaseClient,
  userId: string,
  onUpdate: (economy: EconomyState) => void,
  onStatus?: (status: string) => void,
) {
  if (!userId) throw new Error("userId is required");
  const channel = supabase
    .channel(`kic-economy-${userId}`)
    .on("postgres_changes", {
      event: "UPDATE",
      schema: "public",
      table: "game_admin_player_economy",
      filter: `user_id=eq.${userId}`,
    }, (payload) => {
      // RLS plus filter ensure only the logged-in user's own economy should be delivered.
      onUpdate(payload.new as EconomyState);
    })
    .subscribe((status) => onStatus?.(status));

  return () => { void supabase.removeChannel(channel); };
}

export async function loadMyRuntimeState(supabase: SupabaseClient) {
  const { data, error } = await supabase.rpc("get_my_game_runtime_state");
  if (error) throw new Error(`Gagal memuat runtime state: ${error.message}`);
  return data;
}
