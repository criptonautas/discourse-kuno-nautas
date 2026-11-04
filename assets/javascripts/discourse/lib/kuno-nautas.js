export function formatXmr(amount) {
  const formatter = new Intl.NumberFormat(undefined, {
    maximumFractionDigits: 4,
  });
  return `${formatter.format(Number(amount) || 0)} XMR`;
}

export function campaignCategoryIds(setting) {
  return String(setting || "")
    .split("|")
    .map((id) => parseInt(id, 10))
    .filter((id) => Number.isInteger(id));
}

// Percentage of the goal, capped so the bar never overflows; no goal, no bar.
export function progress(campaign) {
  const goal = Number(campaign?.goal) || 0;
  if (goal <= 0) {
    return null;
  }
  const raw = ((Number(campaign.raised) || 0) / goal) * 100;
  return { percentage: Math.round(raw), width: Math.min(100, raw) };
}
