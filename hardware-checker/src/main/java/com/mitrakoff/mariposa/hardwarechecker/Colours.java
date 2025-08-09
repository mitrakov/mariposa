package com.mitrakoff.mariposa.hardwarechecker;

/**
 * Example: Colours.styles(Colours.CYAN).println("Current time: %d msec", System.currentTimeMillis());
 */
public class Colours {
    // Reset
    public static final String RESET = "\u001B[0m";

    // Regular Colors (30-37)
    public static final String BLACK = "\u001B[30m";
    public static final String RED = "\u001B[31m";
    public static final String GREEN = "\u001B[32m";
    public static final String YELLOW = "\u001B[33m";
    public static final String BLUE = "\u001B[34m";
    public static final String PURPLE = "\u001B[35m";
    public static final String CYAN = "\u001B[36m";
    public static final String WHITE = "\u001B[37m";

    // Bright Colors (90-97)
    public static final String BRIGHT_BLACK = "\u001B[90m";
    public static final String BRIGHT_RED = "\u001B[91m";
    public static final String BRIGHT_GREEN = "\u001B[92m";
    public static final String BRIGHT_YELLOW = "\u001B[93m";
    public static final String BRIGHT_BLUE = "\u001B[94m";
    public static final String BRIGHT_PURPLE = "\u001B[95m";
    public static final String BRIGHT_CYAN = "\u001B[96m";
    public static final String BRIGHT_WHITE = "\u001B[97m";

    // Background Colors (40-47)
    public static final String BLACK_BG = "\u001B[40m";
    public static final String RED_BG = "\u001B[41m";
    public static final String GREEN_BG = "\u001B[42m";
    public static final String YELLOW_BG = "\u001B[43m";
    public static final String BLUE_BG = "\u001B[44m";
    public static final String PURPLE_BG = "\u001B[45m";
    public static final String CYAN_BG = "\u001B[46m";
    public static final String WHITE_BG = "\u001B[47m";

    // Bright Background Colors (100-107)
    public static final String BRIGHT_BLACK_BG = "\u001B[100m";
    public static final String BRIGHT_RED_BG = "\u001B[101m";
    public static final String BRIGHT_GREEN_BG = "\u001B[102m";
    public static final String BRIGHT_YELLOW_BG = "\u001B[103m";
    public static final String BRIGHT_BLUE_BG = "\u001B[104m";
    public static final String BRIGHT_PURPLE_BG = "\u001B[105m";
    public static final String BRIGHT_CYAN_BG = "\u001B[106m";
    public static final String BRIGHT_WHITE_BG = "\u001B[107m";

    // Text Styles
    public static final String BOLD = "\u001B[1m";
    public static final String DIM = "\u001B[2m";
    public static final String ITALIC = "\u001B[3m";
    public static final String UNDERLINE = "\u001B[4m";
    public static final String SLOW_BLINK = "\u001B[5m";
    public static final String RAPID_BLINK = "\u001B[6m";
    public static final String REVERSE = "\u001B[7m";
    public static final String STRIKETHROUGH = "\u001B[9m";

    // Double underline and overline (not widely supported)
    public static final String DOUBLE_UNDERLINE = "\u001B[21m";
    public static final String OVERLINE = "\u001B[53m";

    // Reset specific styles
    public static final String RESET_BOLD = "\u001B[22m";
    public static final String RESET_DIM = "\u001B[22m";
    public static final String RESET_ITALIC = "\u001B[23m";
    public static final String RESET_UNDERLINE = "\u001B[24m";
    public static final String RESET_BLINK = "\u001B[25m";
    public static final String RESET_REVERSE = "\u001B[27m";
    public static final String RESET_STRIKETHROUGH = "\u001B[29m";

    public static Builder styles(String... styles) {
        final StringBuilder sb = new StringBuilder();
        for (String style : styles)
            sb.append(style);
        return new Builder(sb);
    }

    public static String colour256(int colorCode) {
        return "\u001B[38;5;" + colorCode + "m";
    }

    public static String background256(int colorCode) {
        return "\u001B[48;5;" + colorCode + "m";
    }

    // RGB color support methods (24-bit true color)
    public static String rgb(int r, int g, int b) {
        return "\u001B[38;2;" + r + ";" + g + ";" + b + "m";
    }

    public static String rgbBackground(int r, int g, int b) {
        return "\u001B[48;2;" + r + ";" + g + ";" + b + "m";
    }

    public static class Builder {
        private final StringBuilder sb;
        public Builder(StringBuilder sb) {this.sb = sb;}

        public void println(String s, Object... args) {
            if (args.length == 0) sb.append(s);
            else sb.append(String.format(s, args));
            sb.append(RESET);
            System.out.println(sb);
        }
    }
}
