package com.burgerdlc;

import net.minecraft.client.gui.Click;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.input.KeyInput;
import net.minecraft.text.Text;
import net.minecraft.util.math.MathHelper;
import org.lwjgl.glfw.GLFW;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.IntConsumer;

/** Квадратное меню: шапка, категории слева, карточки модулей справа. Перетаскивается за шапку. */
public class ClickGui extends Screen {
    static final int PANEL = 0xE6141420;
    static final int SIDEBAR = 0x40000000;
    static final int CARD = 0xFF1C1C2A;
    static final int CARD_HOVER = 0xFF222234;
    static final int LINE = 0xFF2A2A3C;
    /** Цвет акцента, обновляется из темы каждый кадр. */
    static int ACCENT = 0xFFFF9A1F;
    static final int TEXT = 0xFFE6E6F0;
    static final int DIM = 0xFF8A8AA0;
    static final int OFF = 0xFF34344A;

    private static final int HEADER = 28, SIDE = 84, CARD_HEAD = 30, GAP = 6;
    static final int CENTER = Integer.MIN_VALUE;

    /** Позиция окна; CENTER — по центру экрана. Сохраняется в конфиг. */
    static int posX = CENTER, posY = CENTER;

    static Category current = Category.COMBAT;
    static final Set<Module> expanded = new HashSet<>();
    private static final Map<Object, Float> anim = new HashMap<>();

    private record Hit(int x, int y, int w, int h, boolean clipped, IntConsumer action) {
        boolean contains(double mx, double my) {
            return mx >= x && mx < x + w && my >= y && my < y + h;
        }
    }

    private final List<Hit> hits = new ArrayList<>();
    private int px, py, size, cx, cy, cw, ch;
    private double scroll, scrollTarget, mouseX;
    private Setting.Num dragging;
    private int dragX, dragW;
    private boolean moving;
    private double moveOffX, moveOffY;
    private Module listening;
    private float open;
    private long lastFrame = System.nanoTime();
    private float dt;

    public ClickGui() {
        super(Text.literal("Burger DLC"));
    }

    @Override
    protected void init() {
        size = Math.min(360, Math.min(width, height) - 16);
        place(posX == CENTER ? (width - size) / 2 : posX, posY == CENTER ? (height - size) / 2 : posY);
    }

    private void place(int x, int y) {
        px = MathHelper.clamp(x, 0, Math.max(0, width - size));
        py = MathHelper.clamp(y, 0, Math.max(0, height - size));
        cx = px + SIDE + 8;
        cy = py + HEADER + 8;
        cw = size - SIDE - 16;
        ch = size - HEADER - 16;
    }

    private float animate(Object key, float target, float speed) {
        float v = anim.getOrDefault(key, target);
        v += (target - v) * Math.min(1f, dt * speed);
        anim.put(key, v);
        return v;
    }

    @Override
    public void render(DrawContext ctx, int mx, int my, float delta) {
        super.render(ctx, mx, my, delta);
        long now = System.nanoTime();
        dt = Math.min((now - lastFrame) / 1e9f, 0.1f);
        lastFrame = now;
        open += (1 - open) * Math.min(1f, dt * 14);
        hits.clear();

        lastMx = mx;
        lastMy = my;
        if (moving) {
            place((int) (mx - moveOffX), (int) (my - moveOffY));
            posX = px;
            posY = py;
        }
        if (dragging != null) dragging.set(dragging.min
                + MathHelper.clamp((mx - dragX) / (double) dragW, 0, 1) * (dragging.max - dragging.min));

        var m = ctx.getMatrices();
        m.pushMatrix();
        float s = scale();
        float ox = px + size / 2f, oy = py + size / 2f;
        m.translate(ox, oy);
        m.scale(s, s);
        m.translate(-ox, -oy);

        Render2D.round(ctx, px - 1, py - 1, size + 2, size + 2, 9, LINE);
        Render2D.round(ctx, px, py, size, size, 8, PANEL);

        // Шапка — за неё окно перетаскивается
        Render2D.round(ctx, px + 10, py + 8, 12, 12, 3, ACCENT);
        ctx.drawText(textRenderer, "B", px + 14, py + 10, TEXT, false);
        ctx.drawText(textRenderer, "Burger DLC", px + 28, py + 10, TEXT, false);
        String user = client.getSession().getUsername();
        ctx.drawText(textRenderer, user, px + size - 10 - textRenderer.getWidth(user), py + 10, DIM, false);
        ctx.fill(px, py + HEADER, px + size, py + HEADER + 1, LINE);
        hits.add(new Hit(px, py, size, HEADER, false, b -> {
            moving = true;
            moveOffX = mouseX - px;
            moveOffY = lastMouseY - py;
        }));

        // Категории
        ctx.fill(px, py + HEADER + 1, px + SIDE, py + size - 8, SIDEBAR);
        ctx.fill(px + SIDE, py + HEADER + 1, px + SIDE + 1, py + size, LINE);
        ctx.drawText(textRenderer, "Категории", px + 10, py + HEADER + 8, DIM, false);
        Category[] cats = Category.values();
        for (int i = 0; i < cats.length; i++) {
            Category c = cats[i];
            int y = py + HEADER + 22 + i * 20;
            boolean hover = mx >= px + 6 && mx < px + SIDE - 6 && my >= y && my < y + 16;
            float sel = animate(c, c == current ? 1 : 0, 12);
            if (sel > 0.01f || hover) {
                Render2D.round(ctx, px + 6, y, SIDE - 12, 16, 4,
                        Render2D.mix(0x14FFFFFF, (ACCENT & 0xFFFFFF) | 0x30000000, sel));
            }
            if (sel > 0.01f) ctx.fill(px + 6, y + 4, px + 8, y + 12, Render2D.mix(ACCENT & 0xFFFFFF, ACCENT, sel));
            ctx.drawText(textRenderer, c.title, px + 14, y + 4, Render2D.mix(DIM, TEXT, Math.max(sel, hover ? 0.6f : 0)), false);
            hits.add(new Hit(px + 6, y, SIDE - 12, 16, false, b -> {
                if (current != c) {
                    current = c;
                    scroll = scrollTarget = 0;
                }
            }));
        }
        String hint = listening != null ? "Жми клавишу" : "СКМ — бинд";
        ctx.drawText(textRenderer, hint, px + 10, py + size - 20, listening != null ? ACCENT : DIM, false);

        renderModules(ctx, mx, my);
        m.popMatrix();
    }

    private float scale() {
        return 0.92f + 0.08f * open;
    }

    private void renderModules(DrawContext ctx, int mx, int my) {
        scroll += (scrollTarget - scroll) * Math.min(1f, dt * 16);
        ctx.enableScissor(cx, cy, cx + cw, cy + ch);
        boolean inside = mx >= cx && mx < cx + cw && my >= cy && my < cy + ch;
        int y = cy - (int) Math.round(scroll);
        int total = 0;

        for (Module mod : BurgerDLC.MODULES) {
            if (mod.category != current) continue;
            int full = settingsHeight(mod);
            float ex = animate("expand:" + mod.name, expanded.contains(mod) ? 1 : 0, 14);
            int h = CARD_HEAD + Math.round(full * ex);

            boolean hover = inside && my >= y && my < y + CARD_HEAD;
            Render2D.round(ctx, cx, y, cw, h, 6, hover ? CARD_HOVER : CARD);
            ctx.drawText(textRenderer, mod.name, cx + 8, y + 6, TEXT, false);
            // Бинд
            String bind = listening == mod ? "..." : Binds.name(mod.bind);
            int bw = textRenderer.getWidth(bind) + 8, bx = cx + cw - 36 - bw, by = y + 9;
            ctx.drawText(textRenderer, trim(mod.description, bx - cx - 12), cx + 8, y + 17, DIM, false);
            Render2D.round(ctx, bx, by, bw, 12, 3, listening == mod ? ACCENT : OFF);
            ctx.drawText(textRenderer, bind, bx + 4, by + 2, TEXT, false);
            hits.add(new Hit(bx, by, bw, 12, true, b -> listening = listening == mod ? null : mod));

            // Переключатель
            float on = animate(mod, mod.isEnabled() ? 1 : 0, 14);
            int sx = cx + cw - 30, sy = y + 9;
            Render2D.round(ctx, sx, sy, 22, 12, 6, Render2D.mix(OFF, ACCENT, on));
            Render2D.round(ctx, sx + 2 + Math.round(10 * on), sy + 2, 8, 8, 4, TEXT);
            hits.add(new Hit(sx - 4, y, 34, CARD_HEAD, true, b -> mod.toggle()));

            hits.add(new Hit(cx, y, cw, CARD_HEAD, true, b -> {
                if (b == 2) listening = mod;
                else if (!mod.settings.isEmpty() && !expanded.remove(mod)) expanded.add(mod);
            }));

            if (h > CARD_HEAD) {
                ctx.fill(cx + 8, y + CARD_HEAD - 1, cx + cw - 8, y + CARD_HEAD, LINE);
                ctx.enableScissor(cx, Math.max(cy, y + CARD_HEAD), cx + cw, Math.min(cy + ch, y + h));
                int sy2 = y + CARD_HEAD + 4;
                for (Setting st : mod.settings) {
                    sy2 += renderSetting(ctx, st, cx + 8, sy2, cw - 16, mx, my, sy2 < y + h);
                }
                ctx.disableScissor();
            }
            y += h + GAP;
            total += h + GAP;
        }
        ctx.disableScissor();

        double max = Math.max(0, total - GAP - ch);
        scrollTarget = MathHelper.clamp(scrollTarget, 0, max);
        if (max > 0) {
            int barH = Math.max(20, (int) (ch * ch / (double) (total - GAP)));
            int barY = cy + (int) ((ch - barH) * (scroll / max));
            ctx.fill(px + size - 4, barY, px + size - 2, barY + barH, LINE);
        }
    }

    private static final int PICKER = 58;

    private static int rowHeight(Setting s) {
        if (s instanceof Setting.Color c) return c.open ? 18 + PICKER : 18;
        return s instanceof Setting.Num ? 24 : 18;
    }

    private static int settingsHeight(Module m) {
        int h = 8;
        for (Setting s : m.settings) h += rowHeight(s);
        return h;
    }

    private int renderSetting(DrawContext ctx, Setting s, int x, int y, int w, int mx, int my, boolean visible) {
        int rh = rowHeight(s);
        String value = s instanceof Setting.Mode md ? "‹ " + md.get() + " ›"
                : s instanceof Setting.Num n ? n.format() : "";
        int valueW = s instanceof Setting.Bool ? 18 : s instanceof Setting.Color ? 24 : textRenderer.getWidth(value);
        ctx.drawText(textRenderer, trim(s.name, w - valueW - 6), x, y + 5, TEXT, false);

        if (s instanceof Setting.Color c) {
            Render2D.round(ctx, x + w - 24, y + 4, 24, 10, 3, LINE);
            Render2D.round(ctx, x + w - 23, y + 5, 22, 8, 3, 0xFF000000 | c.rgb());
            if (visible) hits.add(new Hit(x, y, w, 18, true, btn -> c.open = !c.open));
            if (c.open) renderPicker(ctx, c, x, y + 18, w, visible);
        } else if (s instanceof Setting.Bool b) {
            float on = animate(b, b.value ? 1 : 0, 14);
            int sx = x + w - 18, sy = y + 4;
            Render2D.round(ctx, sx, sy, 18, 10, 5, Render2D.mix(OFF, ACCENT, on));
            Render2D.round(ctx, sx + 2 + Math.round(8 * on), sy + 2, 6, 6, 3, TEXT);
            if (visible) hits.add(new Hit(x, y, w, rh, true, btn -> b.value = !b.value));
        } else if (s instanceof Setting.Mode md) {
            ctx.drawText(textRenderer, value, x + w - valueW, y + 5, ACCENT, false);
            if (visible) hits.add(new Hit(x, y, w, rh, true, btn -> md.cycle(btn == 1 ? -1 : 1)));
        } else if (s instanceof Setting.Num n) {
            ctx.drawText(textRenderer, value, x + w - valueW, y + 5, DIM, false);
            int by = y + 17;
            float f = animate(n, (float) n.fraction(), 20);
            Render2D.round(ctx, x, by, w, 3, 1, OFF);
            Render2D.round(ctx, x, by, Math.max(3, Math.round(w * f)), 3, 1, ACCENT);
            int kx = x + Math.round((w - 7) * f);
            boolean hover = mx >= x && mx < x + w && my >= by - 4 && my < by + 7;
            Render2D.round(ctx, kx, by - 2, 7, 7, 3, hover || dragging == n ? 0xFFFFFFFF : TEXT);
            if (visible) hits.add(new Hit(x, y + 12, w, 12, true, btn -> {
                dragging = n;
                dragX = x;
                dragW = w;
                n.set(n.min + MathHelper.clamp((mouseX - x) / w, 0, 1) * (n.max - n.min));
            }));
        }
        return rh;
    }

    /** Пипетка: квадрат насыщенность/яркость и полоса оттенка. */
    private void renderPicker(DrawContext ctx, Setting.Color c, int x, int y, int w, boolean visible) {
        int boxH = PICKER - 16;
        if (pickColor == c) {
            float fx = (float) MathHelper.clamp((lastMx - x) / (double) w, 0, 1);
            if (pickHue) c.hue = fx;
            else {
                c.sat = fx;
                c.bri = 1 - (float) MathHelper.clamp((lastMy - y) / (double) boxH, 0, 1);
            }
        }
        for (int i = 0; i < w; i += 2) {
            int top = 0xFF000000 | java.awt.Color.HSBtoRGB(c.hue, i / (float) w, 1f);
            ctx.fillGradient(x + i, y, x + Math.min(w, i + 2), y + boxH, top, 0xFF000000);
        }
        int kx = x + Math.round(c.sat * (w - 1)), ky = y + Math.round((1 - c.bri) * (boxH - 1));
        ctx.drawStrokedRectangle(kx - 2, ky - 2, 5, 5, 0xFFFFFFFF);
        int hy = y + boxH + 5;
        for (int i = 0; i < w; i += 2) {
            ctx.fill(x + i, hy, x + Math.min(w, i + 2), hy + 6, 0xFF000000 | java.awt.Color.HSBtoRGB(i / (float) w, 1f, 1f));
        }
        int hx = x + Math.round(c.hue * (w - 1));
        ctx.fill(hx - 1, hy - 1, hx + 2, hy + 7, 0xFFFFFFFF);
        if (visible) {
            hits.add(new Hit(x, y, w, boxH, true, btn -> {
                pickColor = c;
                pickHue = false;
            }));
            hits.add(new Hit(x, hy - 2, w, 10, true, btn -> {
                pickColor = c;
                pickHue = true;
            }));
        }
    }

    private Setting.Color pickColor;
    private boolean pickHue;
    private double lastMx, lastMy;

    private String trim(String text, int maxWidth) {
        if (textRenderer.getWidth(text) <= maxWidth) return text;
        return textRenderer.trimToWidth(text, Math.max(0, maxWidth - textRenderer.getWidth("…"))) + "…";
    }

    private double lastMouseY;

    @Override
    public boolean mouseClicked(Click click, boolean doubled) {
        // Переводим координаты мыши с учётом анимации масштаба.
        float s = scale();
        double ox = px + size / 2.0, oy = py + size / 2.0;
        double mx = ox + (click.x() - ox) / s, my = oy + (click.y() - oy) / s;
        int button = click.button();
        mouseX = mx;
        lastMouseY = my;

        if (listening != null && button > 2) {
            listening.bind = Binds.mouse(button);
            listening = null;
            return true;
        }
        boolean inContent = mx >= cx && mx < cx + cw && my >= cy && my < cy + ch;
        for (int i = hits.size() - 1; i >= 0; i--) {
            Hit h = hits.get(i);
            if (h.contains(mx, my) && (!h.clipped || inContent)) {
                h.action.accept(button);
                return true;
            }
        }
        listening = null;
        return super.mouseClicked(click, doubled);
    }

    @Override
    public boolean mouseReleased(Click click) {
        dragging = null;
        pickColor = null;
        moving = false;
        return super.mouseReleased(click);
    }

    @Override
    public boolean mouseScrolled(double mx, double my, double h, double v) {
        scrollTarget -= v * 24;
        return true;
    }

    @Override
    public boolean keyPressed(KeyInput input) {
        int key = input.key();
        if (listening != null) {
            boolean clear = key == GLFW.GLFW_KEY_ESCAPE || key == GLFW.GLFW_KEY_BACKSPACE || key == GLFW.GLFW_KEY_DELETE;
            listening.bind = clear ? Binds.NONE : key;
            listening = null;
            return true;
        }
        if (key == GLFW.GLFW_KEY_RIGHT_SHIFT) {
            close();
            return true;
        }
        return super.keyPressed(input);
    }

    @Override
    public void close() {
        BurgerDLC.saveConfig();
        super.close();
    }

    @Override
    public boolean shouldPause() {
        return false;
    }
}
