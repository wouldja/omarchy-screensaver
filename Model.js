function clamp(value, min, max) {
  var n = Number(value)
  if (!isFinite(n)) return min
  return Math.max(min, Math.min(max, n))
}

function asBool(value, fallback) {
  if (value === true || value === false) return value
  var s = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  if (s === "true" || s === "1" || s === "yes" || s === "on") return true
  if (s === "false" || s === "0" || s === "no" || s === "off") return false
  return fallback
}

var minuteStops = [1, 2, 3, 5, 10, 15, 30]

function nearestMinuteStop(minutes) {
  var m = clamp(minutes, 1, 30)
  var best = 0
  var bestDist = 1e9
  for (var i = 0; i < minuteStops.length; i++) {
    var d = Math.abs(minuteStops[i] - m)
    if (d < bestDist) { bestDist = d; best = i }
  }
  return best
}

function minutesFromSeconds(seconds) {
  return minuteStops[nearestMinuteStop(Math.round(Number(seconds) / 60))]
}

function stops() {
  return minuteStops
}

function secondsFromMinutes(minutes) {
  return minuteStops[nearestMinuteStop(minutes)] * 60
}

function durationLabel(minutes) {
  var n = minuteStops[nearestMinuteStop(minutes)]
  return n === 1 ? "1 MINUTE" : n + " MINUTES"
}

function emptyState() {
  return {
    enabled: true,
    seconds: 150,
    pauseOnVideo: true
  }
}

function parseState(raw) {
  var state = emptyState()
  var parsed = null
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { return state }
  if (!parsed || typeof parsed !== "object") return state
  state.enabled = asBool(parsed.enabled, true)
  state.seconds = clamp(Number(parsed.seconds), 60, 1800)
  if (!isFinite(state.seconds)) state.seconds = 150
  state.seconds = Math.round(state.seconds)
  state.pauseOnVideo = asBool(parsed.pauseOnVideo, true)
  return state
}

function anyPlayerPlaying(players) {
  if (!players || !players.length) return false
  for (var i = 0; i < players.length; i++) {
    var p = players[i]
    if (p && p.isPlaying) return true
  }
  return false
}
