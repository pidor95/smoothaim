package com.example.smoothaim;

public enum Category {
    COMBAT("Combat"),
    MOVEMENT("Movement"),
    DISPLAY("Display");

    public final String title;

    Category(String title) {
        this.title = title;
    }
}
