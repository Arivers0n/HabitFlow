#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// «Желе»: персонаж пружинит от касаний, дышит и сплющивается при приземлении.
// Для каждой точки результата возвращаем, откуда брать цвет в исходной картинке.
//
// size    — размер слоя (с запасом по краям, чтобы растяжение не обрезалось)
// touch   — точка последнего касания в координатах слоя
// age     — сколько секунд прошло с касания
// amp     — сила касания (0…1.5)
// squash  — >0 сплющить, <0 вытянуть (якорь — низ персонажа)
// time    — общее время для дыхания и покачивания
// breathe — сила дыхания (0…1)
// pad     — доля запаса по краям слоя
[[ stitchable ]] float2 petJelly(float2 position, float2 size, float2 touch, float age, float amp,
                                 float squash, float time, float breathe, float pad) {
    float2 p = position;

    // Низ персонажа (с учётом запаса снизу) — ось для сплющивания.
    float bottom = size.y * (1.0 - pad);
    float cx = size.x * 0.5;
    float height = size.y * (1.0 - 2.0 * pad);
    float fromBottom = clamp((bottom - p.y) / max(height, 1.0), 0.0, 1.2);

    // Дыхание: лёгкое сжатие-растяжение.
    float breath = breathe * 0.018 * sin(time * 2.1);
    float s = squash + breath;

    // Сплющивание: точка результата берёт цвет «выше» в источнике и ближе к центру по ширине.
    p.y = bottom - (bottom - p.y) * (1.0 + s);
    p.x = cx + (p.x - cx) * (1.0 - s * 0.6);

    // Затухающие колебания от касания.
    float decay = exp(-3.6 * age);
    float wob = amp * decay * sin(age * 21.0);

    // Желе вокруг точки касания.
    float2 d = position - touch;
    float dist = length(d) / max(size.x, size.y);
    float fall = exp(-dist * dist * 9.0);
    float len = max(length(d), 0.001);
    p += (d / len) * wob * fall * size.x * 0.045;

    // Верх качается сильнее низа.
    p.x += wob * fromBottom * fromBottom * size.x * 0.05 * sin(fromBottom * 2.5 + age * 9.0);
    p.y += wob * fromBottom * size.y * 0.02 * cos(age * 17.0);

    return p;
}

// Блик глянца: светлое пятно, которое плывёт при наклоне телефона.
[[ stitchable ]] half4 petGloss(float2 position, half4 color, float2 size, float2 light, float strength) {
    if (color.a < 0.01h) { return color; }
    float2 uv = position / size;
    float2 c = float2(0.5, 0.35) + light * 0.25;
    float d = distance(uv, c);
    float g = smoothstep(0.42, 0.0, d) * strength;
    // Тонкая кромка света по краю силуэта даёт объём.
    half3 lit = color.rgb + half3(g * 0.55) * color.a;
    return half4(min(lit, color.a), color.a);
}
