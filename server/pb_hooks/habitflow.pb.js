/// <reference path="../pb_data/types.d.ts" />
// Маршруты HabitFlow на сервере Копилки. Аккаунты общие (коллекция users), данные — отдельные.

routerAdd("GET", "/api/hf/ping", (e) => {
    return e.json(200, { ok: true, app: "habitflow", version: 1 })
})

// Забрать изменения после курсора since (серверное время записи).
routerAdd("POST", "/api/hf/pull", (e) => {
    const body = e.requestInfo().body || {}
    const since = Number(body.since || 0)
    const limit = 500
    const recs = e.app.findRecordsByFilter("hf_docs", "owner = {:o} && srv > {:since}", "srv", limit + 1, 0,
                                           { o: e.auth.id, since: since })
    const out = []
    let cursor = since
    for (const r of recs.slice(0, limit)) {
        let data = {}
        try { data = JSON.parse(r.getString("data") || "{}") } catch (_) {}
        out.push({ cid: r.getString("cid"), kind: r.getString("kind"), data: data,
                   deleted: r.getBool("deleted"), cts: r.getFloat("cts"), srv: r.getFloat("srv") })
        cursor = r.getFloat("srv")
    }
    return e.json(200, { docs: out, cursor: cursor, more: recs.length > limit })
}, $apis.requireAuth("users"))

// Отправить изменения. Побеждает более свежая правка (по времени клиента).
routerAdd("POST", "/api/hf/push", (e) => {
    const body = e.requestInfo().body || {}
    const docs = Array.isArray(body.docs) ? body.docs.slice(0, 500) : []
    const col = e.app.findCollectionByNameOrId("hf_docs")
    const base = Date.now() * 1000
    let i = 0, saved = 0, skipped = 0
    for (const d of docs) {
        const cid = String(d.cid || "").slice(0, 80)
        if (!cid) continue
        let rec = null
        try { rec = e.app.findFirstRecordByFilter("hf_docs", "owner = {:o} && cid = {:c}", { o: e.auth.id, c: cid }) } catch (_) {}
        const cts = Number(d.cts || 0)
        if (rec && rec.getFloat("cts") > cts) { skipped++; continue }
        if (!rec) { rec = new Record(col); rec.set("owner", e.auth.id); rec.set("cid", cid) }
        rec.set("kind", String(d.kind || "").slice(0, 30))
        rec.set("data", d.data || {})
        rec.set("deleted", !!d.deleted)
        rec.set("cts", cts)
        rec.set("srv", base + (i++))
        e.app.save(rec)
        saved++
    }
    return e.json(200, { saved: saved, skipped: skipped })
}, $apis.requireAuth("users"), $apis.bodyLimit(8 << 20))

// Публичная карточка для друзей: имя, напарник, уровень и серии тех привычек, которые пользователь разрешил показывать.
routerAdd("POST", "/api/hf/profile", (e) => {
    const u = require(`${__hooks}/hf_utils.js`)
    const body = e.requestInfo().body || {}
    const data = body.data && typeof body.data === "object" ? body.data : {}
    if (JSON.stringify(data).length > 60000) throw new BadRequestError("Слишком большая карточка")
    const rec = u.ensureProfile(e.app, e.auth.id)
    rec.set("data", data)
    e.app.save(rec)
    const cheers = u.parse(rec, "cheers", [])
    return e.json(200, { ok: true, cheers: cheers.slice(-30) })
}, $apis.requireAuth("users"))

// Круги друзей и семьи с карточками участников.
routerAdd("POST", "/api/hf/circles", (e) => {
    const u = require(`${__hooks}/hf_utils.js`)
    const body = e.requestInfo().body || {}
    const dayStart = Number(body.dayStart || 0)
    const list = u.userCircles(e.app, e.auth.id).map((r) => u.circleJSON(e.app, r, e.auth.id, dayStart))
    const me = u.profile(e.app, e.auth.id)
    const cheers = me ? u.parse(me, "cheers", []) : []
    return e.json(200, { circles: list, cheers: cheers.slice(-30) })
}, $apis.requireAuth("users"))

routerAdd("POST", "/api/hf/circle/create", (e) => {
    const u = require(`${__hooks}/hf_utils.js`)
    const body = e.requestInfo().body || {}
    if (u.userCircles(e.app, e.auth.id).length >= 20) throw new BadRequestError("Можно состоять максимум в 20 кругах")
    const name = String(body.name || "Друзья").trim().slice(0, 80) || "Друзья"
    const rec = new Record(e.app.findCollectionByNameOrId("hf_circles"))
    rec.set("name", name)
    rec.set("owner", e.auth.id)
    rec.set("members", [e.auth.id])
    rec.set("code", u.newCode())
    e.app.save(rec)
    return e.json(200, { circle: u.circleJSON(e.app, rec, e.auth.id, Number(body.dayStart || 0)) })
}, $apis.requireAuth("users"))

routerAdd("POST", "/api/hf/circle/join", (e) => {
    const u = require(`${__hooks}/hf_utils.js`)
    const body = e.requestInfo().body || {}
    const code = String(body.code || "").trim().toUpperCase().replace(/[^A-Z0-9]/g, "")
    if (code.length < 4) throw new BadRequestError("Введите код приглашения")
    let rec
    try { rec = e.app.findFirstRecordByFilter("hf_circles", "code = {:c}", { c: code }) }
    catch (_) { throw new NotFoundError("Код не найден. Проверьте его у того, кто пригласил.") }
    const m = u.members(rec)
    if (m.indexOf(e.auth.id) < 0) {
        if (m.length >= 50) throw new BadRequestError("В круге уже 50 человек")
        m.push(e.auth.id); rec.set("members", m); e.app.save(rec)
    }
    return e.json(200, { circle: u.circleJSON(e.app, rec, e.auth.id, Number(body.dayStart || 0)) })
}, $apis.requireAuth("users"))

// Выйти из круга. Если выходит владелец — права переходят следующему, пустой круг удаляется.
routerAdd("POST", "/api/hf/circle/leave", (e) => {
    const u = require(`${__hooks}/hf_utils.js`)
    const body = e.requestInfo().body || {}
    const rec = u.requireCircle(e.app, String(body.circle || ""), e.auth.id)
    const m = u.members(rec).filter((x) => x !== e.auth.id)
    if (m.length === 0) { e.app.delete(rec); return e.json(200, { ok: true }) }
    rec.set("members", m)
    if (rec.getString("owner") === e.auth.id) rec.set("owner", m[0])
    e.app.save(rec)
    return e.json(200, { ok: true })
}, $apis.requireAuth("users"))

// Переименовать, обновить код или убрать участника (только владелец).
routerAdd("POST", "/api/hf/circle/update", (e) => {
    const u = require(`${__hooks}/hf_utils.js`)
    const body = e.requestInfo().body || {}
    const rec = u.requireCircle(e.app, String(body.circle || ""), e.auth.id)
    if (rec.getString("owner") !== e.auth.id) throw new ForbiddenError("Это может только создатель круга")
    if (body.name) rec.set("name", String(body.name).trim().slice(0, 80))
    if (body.newCode) rec.set("code", u.newCode())
    if (body.kick && body.kick !== e.auth.id) rec.set("members", u.members(rec).filter((x) => x !== body.kick))
    e.app.save(rec)
    return e.json(200, { circle: u.circleJSON(e.app, rec, e.auth.id, Number(body.dayStart || 0)) })
}, $apis.requireAuth("users"))

// «Поддержать»: отправить другу хлопок. Не чаще раза в 10 минут одному человеку.
routerAdd("POST", "/api/hf/cheer", (e) => {
    const u = require(`${__hooks}/hf_utils.js`)
    const body = e.requestInfo().body || {}
    const to = String(body.to || "")
    const circle = u.requireCircle(e.app, String(body.circle || ""), e.auth.id)
    if (!to || to === e.auth.id || !u.isMember(circle, to)) throw new BadRequestError("Этого человека нет в круге")
    const key = "hfcheer:" + e.auth.id + ":" + to
    const last = Number(e.app.store().get(key) || 0)
    if (Date.now() - last < 10 * 60 * 1000) return e.json(429, { message: "Вы уже поддержали его недавно" })
    e.app.store().set(key, Date.now())

    const myProfile = u.profile(e.app, e.auth.id)
    const myData = myProfile ? u.parse(myProfile, "data", {}) : {}
    const rec = u.ensureProfile(e.app, to)
    const cheers = u.parse(rec, "cheers", [])
    cheers.push({
        from: e.auth.id,
        name: (myData && myData.name) || u.userName(e.app, e.auth.id),
        companion: (myData && myData.companion) || "",
        emoji: String(body.emoji || "👏").slice(0, 8),
        circle: circle.id,
        ts: Date.now(),
    })
    rec.set("cheers", cheers.slice(-50))
    e.app.save(rec)
    return e.json(200, { ok: true })
}, $apis.requireAuth("users"))

// Ссылка-приглашение: https://СЕРВЕР/api/hf/invite?code=XXXXXX — открывает HabitFlow и вступает в круг.
routerAdd("GET", "/api/hf/invite", (e) => {
    const code = String(e.request.url.query().get("code") || "").replace(/[^A-Za-z0-9]/g, "").slice(0, 12)
    const proto = e.request.header.get("X-Forwarded-Proto") || "https"
    const server = proto + "://" + e.request.host
    const link = "habitflow://join?server=" + encodeURIComponent(server) + (code ? "&code=" + code : "")
    const html = `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>HabitFlow — приглашение</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;background:#07080d;color:#f2f4fa;margin:0;display:flex;min-height:100vh;align-items:center;justify-content:center}
.c{background:#141724;border:1px solid #262b3d;border-radius:26px;padding:28px 24px;max-width:340px;margin:16px;text-align:center}
a.b{display:block;background:linear-gradient(135deg,#4C8DFF,#9B6BFF);color:#fff;text-decoration:none;font-weight:600;padding:15px;border-radius:16px;margin:18px 0 10px}
code{font-size:24px;letter-spacing:3px;font-weight:700}p{color:#a3a9bd;line-height:1.45}</style></head>
<body><div class="c"><h2>HabitFlow</h2><p>Тебя позвали в круг друзей: будете видеть серии друг друга и поддерживать.</p>${code ? "<p>Код приглашения<br><code>" + code + "</code></p>" : ""}
<a class="b" href="${link}">Открыть в HabitFlow</a>
<p style="font-size:13px">Если ничего не происходит — установи HabitFlow, затем нажми кнопку ещё раз. Код можно ввести и вручную: «Прогресс» → «Друзья».</p></div>
<script>setTimeout(function(){location.href=${JSON.stringify(link)}},400)</script></body></html>`
    return e.html(200, html)
})
