// Push copy (English only, doc 15 §2). The app opens `link` (deep links, doc 15 §3).

export interface Rendered {
  title: string;
  body: string;
  link: string;
  /** iOS interruption level / Android priority. */
  urgent: boolean;
}

const str = (v: unknown, fallback = ""): string => (typeof v === "string" && v.length > 0 ? v : fallback);

export function render(type: string, payload: Record<string, unknown>): Rendered | null {
  const who = str(payload.username, "A friend");
  switch (type) {
    case "friend_request":
      return {
        title: "New friend request",
        body: `${who} wants to be friends on Pushly.`,
        link: "pushly://friends",
        urgent: false,
      };
    case "friend_accepted":
      return {
        title: "You're friends now",
        body: `${who} accepted your friend request.`,
        link: `pushly://u/${who}`,
        urgent: false,
      };
    case "kudos":
      return { title: "👊 Kudos!", body: `${who} gave you kudos.`, link: "pushly://friends", urgent: false };
    case "wake_validated":
      return {
        title: "Wake challenge verified",
        body: str(payload.text, "Your result is in."),
        link: "pushly://wake",
        urgent: false,
      };
    case "achievement":
      return {
        title: "Achievement unlocked",
        body: str(payload.title, "You unlocked a new achievement."),
        link: "pushly://profile/achievements",
        urgent: false,
      };
    case "alarms_running_out":
      return {
        title: "Open Pushly to keep your alarms",
        body: "Your scheduled alarms run out soon. Open the app once to keep them ringing.",
        link: "pushly://settings/alarm-health",
        urgent: true,
      };
    case "streak_at_risk":
      return {
        title: "Your streak needs an alarm",
        body: "No challenge alarm is set for tomorrow.",
        link: "pushly://wake",
        urgent: false,
      };
    default:
      return null;
  }
}
