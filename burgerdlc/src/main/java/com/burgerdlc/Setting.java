package com.burgerdlc;

import net.minecraft.util.math.MathHelper;

public abstract class Setting {
    public final String name;

    protected Setting(String name) {
        this.name = name;
    }

    abstract String save();

    abstract void load(String s);

    public static final class Bool extends Setting {
        public boolean value;

        public Bool(String name, boolean value) {
            super(name);
            this.value = value;
        }

        @Override
        String save() {
            return Boolean.toString(value);
        }

        @Override
        void load(String s) {
            value = Boolean.parseBoolean(s);
        }
    }

    public static final class Num extends Setting {
        public final double min, max, step;
        public double value;

        public Num(String name, double value, double min, double max, double step) {
            super(name);
            this.min = min;
            this.max = max;
            this.step = step;
            set(value);
        }

        public void set(double v) {
            value = MathHelper.clamp(Math.round(v / step) * step, min, max);
        }

        public double fraction() {
            return (value - min) / (max - min);
        }

        public String format() {
            return step >= 1 ? Long.toString(Math.round(value)) : String.format("%.2f", value);
        }

        @Override
        String save() {
            return Double.toString(value);
        }

        @Override
        void load(String s) {
            try {
                set(Double.parseDouble(s));
            } catch (NumberFormatException ignored) {
            }
        }
    }

    public static final class Mode extends Setting {
        public final String[] modes;
        public int index;

        public Mode(String name, String... modes) {
            super(name);
            this.modes = modes;
        }

        public String get() {
            return modes[index];
        }

        public boolean is(String mode) {
            return get().equals(mode);
        }

        public void cycle(int dir) {
            index = Math.floorMod(index + dir, modes.length);
        }

        @Override
        String save() {
            return get();
        }

        @Override
        void load(String s) {
            for (int i = 0; i < modes.length; i++) {
                if (modes[i].equals(s)) index = i;
            }
        }
    }
}
