// Frecency, ported from Raycast (reference/02-backend.md §4.6, SPEC §7.4).
//
// Each item keeps one `anchor` (Unix seconds). Its score decays
// exponentially from the anchor with a 10-day half-life; every launch adds
// 100 to the decayed score and moves the anchor so the new score holds.
// Unvisited items score 1.

var LAMBDA = Math.LN2 / 10            // per day: half-life 10 days [O 0.06931471805599453]
var DAY = 86400                       // seconds [O]
var EXP_GUARD = 709.78                // exp overflow guard [O]
var VISIT_BONUS = 100                 // [O]
var SEARCH_TERM_WINDOW_MS = 1468800000 // 17 days: learned terms count only this long after a launch [O fXi]
var MAX_SEARCH_TERMS = 20             // [I] Raycast's cap was not recovered; enough for ranking

function isNumber(value) {
  return typeof value === "number" && isFinite(value)
}

function score(anchorSec, nowSec) {
  if (!isNumber(anchorSec) || !isNumber(nowSec)) return 1
  return Math.max(1, Math.exp(Math.min(EXP_GUARD, LAMBDA * (anchorSec - nowSec) / DAY)))
}

// New anchor after a launch at nowSec.
function visit(anchorSec, nowSec) {
  var t = Number(nowSec)
  // a = max(anchor_old, t), NaN-safe: a missing anchor counts as t.
  var a = isNumber(anchorSec) ? Math.max(anchorSec, t) : t
  var s = Math.max(1, Math.exp(Math.min(EXP_GUARD, LAMBDA * (a - t) / DAY)))
  var s2 = s + VISIT_BONUS
  if (!(s2 >= 1)) return t
  return t + DAY * Math.log(Math.min(s2, Number.MAX_VALUE)) / LAMBDA
}

// Returns a new entry {anchor, openedAt, searchTerms}; `entry` may be null.
// The launching query is remembered (lowercased, trimmed, newest last).
function recordVisit(entry, nowMs, searchTerm) {
  var prior = entry && typeof entry === "object" ? entry : {}
  var nowSec = nowMs / 1000
  var terms = Array.isArray(prior.searchTerms) ? prior.searchTerms.slice() : []
  var term = String(searchTerm === undefined || searchTerm === null ? "" : searchTerm).trim().toLowerCase()
  if (term) {
    terms = terms.filter(function(t) { return t && t.term !== term })
    terms.push({ term: term, at: nowMs })
    if (terms.length > MAX_SEARCH_TERMS) terms = terms.slice(terms.length - MAX_SEARCH_TERMS)
  }
  return {
    anchor: visit(prior.anchor, nowSec),
    openedAt: nowMs,
    searchTerms: terms
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    LAMBDA: LAMBDA,
    VISIT_BONUS: VISIT_BONUS,
    SEARCH_TERM_WINDOW_MS: SEARCH_TERM_WINDOW_MS,
    MAX_SEARCH_TERMS: MAX_SEARCH_TERMS,
    score: score,
    visit: visit,
    recordVisit: recordVisit
  }
}
