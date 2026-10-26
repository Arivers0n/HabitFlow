/// <reference path="../pb_data/types.d.ts" />
// Коллекции HabitFlow. Живут рядом с Копилкой на том же сервере и не трогают её данные.
// Доступ только через свои маршруты /api/hf/* (правила API = null).

migrate((app) => {
    const exists = (n) => { try { app.findCollectionByNameOrId(n); return true } catch (_) { return false } }

    if (!exists("hf_docs")) {
        app.save(new Collection({
            type: "base",
            name: "hf_docs",
            listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
            fields: [
                { type: "text", name: "owner", required: true, max: 40 },
                { type: "text", name: "cid", required: true, max: 80 },
                { type: "text", name: "kind", max: 30 },
                { type: "json", name: "data", maxSize: 500000 },
                { type: "bool", name: "deleted" },
                { type: "number", name: "cts" },
                { type: "number", name: "srv" },
                { type: "autodate", name: "created", onCreate: true, onUpdate: false },
                { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
            ],
            indexes: [
                "CREATE UNIQUE INDEX idx_hf_docs_owner_cid ON hf_docs (owner, cid)",
                "CREATE INDEX idx_hf_docs_owner_srv ON hf_docs (owner, srv)",
            ],
        }))
    }

    if (!exists("hf_circles")) {
        app.save(new Collection({
            type: "base",
            name: "hf_circles",
            listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
            fields: [
                { type: "text", name: "name", max: 80 },
                { type: "text", name: "code", max: 20 },
                { type: "text", name: "owner", max: 40 },
                { type: "json", name: "members", maxSize: 200000 },
                { type: "autodate", name: "created", onCreate: true, onUpdate: false },
                { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
            ],
            indexes: ["CREATE INDEX idx_hf_circles_code ON hf_circles (code)"],
        }))
    }

    if (!exists("hf_profiles")) {
        app.save(new Collection({
            type: "base",
            name: "hf_profiles",
            listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
            fields: [
                { type: "text", name: "user", required: true, max: 40 },
                { type: "json", name: "data", maxSize: 100000 },
                { type: "json", name: "cheers", maxSize: 100000 },
                { type: "autodate", name: "created", onCreate: true, onUpdate: false },
                { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
            ],
            indexes: ["CREATE UNIQUE INDEX idx_hf_profiles_user ON hf_profiles (user)"],
        }))
    }
}, (app) => {
    for (const n of ["hf_docs", "hf_circles", "hf_profiles"]) {
        try { app.delete(app.findCollectionByNameOrId(n)) } catch (_) {}
    }
})
