// Receives Telegram's webhook calls (button presses from notify-new-location's
// Approve/Reject keyboard) and applies the decision to public.locations.
//
// Deploy: supabase functions deploy telegram-webhook --no-verify-jwt
// Secrets needed (set once): TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically by Supabase.
//
// After deploying, register this URL with Telegram once:
//   https://api.telegram.org/bot<TOKEN>/setWebhook
//     ?url=https://<project-ref>.functions.supabase.co/telegram-webhook
//     &secret_token=<the same TELEGRAM_WEBHOOK_SECRET>

const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN")!;
const TELEGRAM_WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

async function tg(method: string, body: Record<string, unknown>) {
  return fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.serve(async (req) => {
  // Only Telegram (who knows the secret we set via setWebhook) may call this.
  if (req.headers.get("X-Telegram-Bot-Api-Secret-Token") !== TELEGRAM_WEBHOOK_SECRET) {
    return new Response("forbidden", { status: 403 });
  }

  try {
    const update = await req.json();
    const cb = update.callback_query;
    if (!cb) {
      // Not a button press (e.g. a plain message to the bot) - nothing to do.
      return new Response("ok", { status: 200 });
    }

    const [action, id] = String(cb.data ?? "").split(":");
    if (!id || (action !== "approve" && action !== "reject")) {
      await tg("answerCallbackQuery", { callback_query_id: cb.id, text: "Невідома дія" });
      return new Response("ok", { status: 200 });
    }

    const newStatus = action === "approve" ? "approved" : "rejected";

    const patchResp = await fetch(`${SUPABASE_URL}/rest/v1/locations?id=eq.${id}`, {
      method: "PATCH",
      headers: {
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        "Content-Type": "application/json",
        Prefer: "return=representation",
      },
      body: JSON.stringify({ status: newStatus }),
    });
    const rows = await patchResp.json();
    const updated = Array.isArray(rows) && rows.length > 0;

    const chatId = cb.message?.chat?.id;
    const messageId = cb.message?.message_id;
    const statusLabel = newStatus === "approved" ? "✅ СХВАЛЕНО" : "❌ ВІДХИЛЕНО";
    const originalText: string = cb.message?.text ?? cb.message?.caption ?? "";
    const newText = updated
      ? `${originalText}\n\n${statusLabel}`
      : `${originalText}\n\n⚠️ Локацію не знайдено (можливо, вже оброблена)`;

    if (chatId && messageId) {
      if (cb.message?.caption !== undefined) {
        await tg("editMessageCaption", { chat_id: chatId, message_id: messageId, caption: newText, parse_mode: "HTML" });
      } else {
        await tg("editMessageText", { chat_id: chatId, message_id: messageId, text: newText, parse_mode: "HTML" });
      }
      await tg("editMessageReplyMarkup", { chat_id: chatId, message_id: messageId, reply_markup: { inline_keyboard: [] } });
    }

    await tg("answerCallbackQuery", {
      callback_query_id: cb.id,
      text: updated ? statusLabel : "Локацію не знайдено",
    });

    return new Response("ok", { status: 200 });
  } catch (err) {
    console.error(err);
    return new Response("error", { status: 500 });
  }
});
