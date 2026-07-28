import java.util.*;

/** Simple single-file no-dependency no-AST no-Reflection JSON parser */
public final class VanillaJsonParser {
    private final String src;
    private int idx = 0;

    private VanillaJsonParser(String json) {
        this.src = json != null ? json.trim() : "";
    }

    /**
     * Parses JSON into a java Object. You should then manually cast to your expected type
     * <pre>{@code
     * final var config = (Map<String, Object>) VanillaJsonParser.parse(s);
     * final var port = (Number) config.get("port");
     * }</pre>
     * @param json input JSON string
     * @return Map&lt;String,Object> for objects, List&lt;Object> for arrays, Number for numbers, String for strings, Boolean for bools 
     */
    public static Object parse(String json) {
        return new VanillaJsonParser(json).parseValue();
    }

    private Object parseValue() {
        skipWhitespace();
        if (idx >= src.length()) return null;

        char c = src.charAt(idx);
        if (c == '{') return parseObject();
        if (c == '[') return parseArray();
        if (c == '"') return parseString();
        if (c == 't' || c == 'f') return parseBoolean();
        if (c == 'n') return parseNull();
        if (Character.isDigit(c) || c == '-') return parseNumber();

        throw new IllegalArgumentException("Invalid char in position " + idx + ": " + c);
    }

    private Map<String, Object> parseObject() {
        final var map = new LinkedHashMap<String, Object>();
        idx++; // Skip '{'
        skipWhitespace();

        if (idx < src.length() && src.charAt(idx) == '}') {
            idx++; // empty object, why not?
            return map;
        }

        while (idx < src.length()) {
            skipWhitespace();
            if (src.charAt(idx) != '"')
                throw new IllegalArgumentException("Expected `\"` at index " + idx);

            final var key = parseString();
            skipWhitespace();

            if (idx >= src.length() || src.charAt(idx) != ':')
                throw new IllegalArgumentException("Expected `:` at index " + idx);
            idx++; // Skip ':'

            map.put(key, parseValue());

            skipWhitespace();
            if (idx >= src.length())
                throw new IllegalArgumentException("Unexpected end of JSON input at index " + idx);
            final var next = src.charAt(idx);
            if (next == '}') {
                idx++;
                break;
            } else if (next == ',') {
                idx++;
            } else throw new IllegalArgumentException("Expected `,` or `}` at index " + idx);
        }
        return map;
    }

    private List<Object> parseArray() {
        final var list = new ArrayList<>();
        idx++; // Skip '['
        skipWhitespace();

        if (idx < src.length() && src.charAt(idx) == ']') {
            idx++; // Empty array, why not?
            return list;
        }

        while (idx < src.length()) {
            list.add(parseValue());
            skipWhitespace();

            if (idx >= src.length())
                throw new IllegalArgumentException("Unexpected end of JSON array at index " + idx);
            final var next = src.charAt(idx);
            if (next == ']') {
                idx++;
                break;
            } else if (next == ',') {
                idx++;
            } else throw new IllegalArgumentException("Expected `,` or `]` at index " + idx);
        }
        return list;
    }

    private String parseString() {
        idx++; // Skip initial "
        final var start = idx;
        while (idx < src.length()) {
            final var c = src.charAt(idx);
            if (c == '\\') { // Skip escape character (e.g. \")
                idx += 2;
                if (idx >= src.length())
                    throw new IllegalArgumentException("Unterminated escape sequence at index " + (idx - 2));
                continue;
            }
            if (c == '"') {
                String val = src.substring(start, idx);
                idx++; // Skip final "
                return val;
            }
            idx++;
        }
        throw new IllegalArgumentException("Unclosed string at index " + idx);
    }

    private Number parseNumber() {
        int start = idx;
        if (src.charAt(idx) == '-') idx++;
        boolean isFloat = false;

        while (idx < src.length()) {
            char c = src.charAt(idx);
            if (Character.isDigit(c)) idx++;
            else if (c == '.' || c == 'e' || c == 'E') {
                isFloat = true;
                idx++;
            } else break;
        }
        String numStr = src.substring(start, idx);
        return isFloat ? Double.parseDouble(numStr) : Long.parseLong(numStr);
    }

    private Boolean parseBoolean() {
        if (src.startsWith("true", idx)) {
            idx += 4;
            return Boolean.TRUE;
        } else if (src.startsWith("false", idx)) {
            idx += 5;
            return Boolean.FALSE;
        }
        throw new IllegalArgumentException("Error parsing boolean value at " + idx);
    }

    private Object parseNull() {
        if (src.startsWith("null", idx)) {
            idx += 4;
            return null;
        }
        throw new IllegalArgumentException("Error parsing null at index " + idx);
    }

    private void skipWhitespace() {
        while (idx < src.length() && Character.isWhitespace(src.charAt(idx)))
            idx++;
    }
}
