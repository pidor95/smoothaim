package com.burgerdlc;

public enum Category {
    COMBAT("Combat"),
    MOVEMENT("Movement"),
    VISUALS("Visuals"),
    DISPLAY("Display");

    public final String title;

    Category(String title) {
        this.title = title;
    }
}
