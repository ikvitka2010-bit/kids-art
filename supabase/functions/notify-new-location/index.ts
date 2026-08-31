// Called by a Supabase Database Webhook on every INSERT into public.locations.
// Sends the owner a Telegram message with the submission and Approve/Reject buttons.
//
// Deploy: supabase functions deploy notify-new-location --no-verify-jwt
// Secrets needed (set once): TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically by Supabase.

const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN")!;
const TELEGRAM_CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const TYPE_LABEL: Record<string, string> = {
  free: "🆓 Бесплатно",
  mall: "🛍️ ТЦ / крытое",
  nature: "🌳 Природа / парк",
};

function escapeHtml(s: unknown): string {
  return String(s ?? "—")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    // Supabase Database Webhooks send { type: "INSERT", table, record, ... }
    const loc = payload.record;
    if (!loc?.id) {
      return new Response("no record in payload", { status: 400 });
    }

    const text =
      `📍 <b>Нова локація на модерацію!</b>\n\n` +
      `<b>Назва:</b> ${escapeHtml(loc.name_ru)}\n` +
      `<b>Район:</b> ${escapeHtml(loc.district_name_ru)}\n` +
      `<b>Тип:</b> ${TYPE_LABEL[loc.type] ?? escapeHtml(loc.type)}\n` +
      `<b>Карта:</b> ${escapeHtml(loc.map_query)}\n` +
      `<b>Опис:</b> ${escapeHtml(loc.desc_ru)}`;

    const keyboard = {
      inline_keyboard: [
        [
          { text: "✅ Схвалити", callback_data: `approve:${loc.id}` },
          { text: "❌ Відхилити", callback_data: `reject:${loc.id}` },
        ],
      ],
    };

    // A submitted photo is always a full URL (uploaded to Supabase Storage),
    // so it can be sent as an actual photo with the details as its caption.
    const hasPhoto = typeof loc.img === "string" && loc.img.startsWith("http");
    const method = hasPhoto ? "sendPhoto" : "sendMessage";
    const body = hasPhoto
      ? { chat_id: TELEGRAM_CHAT_ID, photo: loc.img, caption: text, parse_mode: "HTML", reply_markup: keyboard }
      : { chat_id: TELEGRAM_CHAT_ID, text, parse_mode: "HTML", reply_markup: keyboard };

    const tgResp = await fetch(
      `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${method}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      },
    );
    const tgData = await tgResp.json();

    // Remember the Telegram message id so the webhook can edit it later.
    if (tgData.ok) {
      await fetch(`${SUPABASE_URL}/rest/v1/locations?id=eq.${loc.id}`, {
        method: "PATCH",
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ telegram_message_id: tgData.result.message_id }),
      });
    }

    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ ok: false, error: String(err) }), {
      status: 500,
    });
  }
});
