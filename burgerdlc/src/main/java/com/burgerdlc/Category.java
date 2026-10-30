package com.burgerdlc;

public enum Category {
    COMBAT("Combat"),
    MOVEMENT("Movement"),
    VISUALS("Visuals"),
    OPTIMIZATION("Optimization"),
    DISPLAY("Display");

    public final String title;

    Category(String title) {
        this.title = title;
    }
}
