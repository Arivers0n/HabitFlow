// Общие функции для маршрутов HabitFlow. Подключаются через require() внутри обработчиков.

function parse(rec, field, fallback) {
    try {
        const v = JSON.parse(rec.getString(field) || "null")
        return v === null || v === undefined ? fallback : v
    } catch (_) { return fallback }
}

function members(rec) {
    const arr = parse(rec, "members", [])
    return Array.isArray(arr) ? arr : []
}

function isMember(rec, uid) {
    return members(rec).indexOf(uid) >= 0
}

function profile(app, uid) {
    try { return app.findFirstRecordByFilter("hf_profiles", "user = {:u}", { u: uid }) } catch (_) { return null }
}

function ensureProfile(app, uid) {
    let rec = profile(app, uid)
    if (!rec) {
        rec = new Record(app.findCollectionByNameOrId("hf_profiles"))
        rec.set("user", uid)
        rec.set("data", {})
        rec.set("cheers", [])
    }
    return rec
}

function userName(app, uid) {
    try {
        const u = app.findRecordById("users", uid)
        const n = u.getString("name")
        if (n) return n
        const e = u.getString("email")
        return e ? e.split("@")[0] : ""
    } catch (_) { return "" }
}

// dayStart — начало «сегодня» у пользователя (мс), чтобы не зависеть от часового пояса сервера.
function circleJSON(app, rec, me, dayStart) {
    const people = []
    for (const id of members(rec)) {
        const p = profile(app, id)
        const data = p ? parse(p, "data", {}) : {}
        const cheers = p ? parse(p, "cheers", []) : []
        const today = cheers.filter((c) => c && c.circle === rec.id && Number(c.ts || 0) >= dayStart)
        people.push({
            id: id,
            name: (data && data.name) || userName(app, id),
            me: id === me,
            profile: data || {},
            cheersToday: today.length,
            cheeredByMe: today.some((c) => c.from === me),
        })
    }
    return {
        id: rec.id,
        name: rec.getString("name"),
        code: rec.getString("code"),
        owner: rec.getString("owner"),
        members: people,
    }
}

function userCircles(app, uid) {
    const found = app.findRecordsByFilter("hf_circles", "members ~ {:q}", "created", 100, 0, { q: '"' + uid + '"' })
    return found.filter((r) => isMember(r, uid))
}

function requireCircle(app, id, uid) {
    let rec
    try { rec = app.findRecordById("hf_circles", id) } catch (_) { throw new NotFoundError("Круг не найден") }
    if (!isMember(rec, uid)) throw new ForbiddenError("Вы не в этом круге")
    return rec
}

function newCode() {
    return $security.randomStringWithAlphabet(6, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
}

module.exports = { parse, members, isMember, profile, ensureProfile, userName, circleJSON, userCircles, requireCircle, newCode }
