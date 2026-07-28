package com.mitrakoff.mariposa;

import java.util.*;

public class VanillaJsonParser {
    private final String src;
    private int idx = 0;

    private VanillaJsonParser(String json) {
        // Limpiamos espacios innecesarios al inicio y final
        this.src = json != null ? json.trim() : "";
    }

    // Punto de entrada único
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

        throw new IllegalArgumentException("Carácter inesperado en posición " + idx + ": " + c);
    }

    private Map<String, Object> parseObject() {
        Map<String, Object> map = new LinkedHashMap<>();
        idx++; // Saltar '{'
        skipWhitespace();

        if (idx < src.length() && src.charAt(idx) == '}') {
            idx++; // Objeto vacío
            return map;
        }

        while (idx < src.length()) {
            skipWhitespace();
            if (src.charAt(idx) != '"') throw new IllegalArgumentException("Se esperaba una clave string en " + idx);

            String key = parseString();
            skipWhitespace();

            if (idx >= src.length() || src.charAt(idx) != ':') throw new IllegalArgumentException("Se esperaba ':' en " + idx);
            idx++; // Saltar ':'

            Object value = parseValue();
            map.put(key, value);

            skipWhitespace();
            char next = src.charAt(idx);
            if (next == '}') {
                idx++;
                break;
            } else if (next == ',') {
                idx++;
            } else {
                throw new IllegalArgumentException("Se esperaba ',' o '}' en " + idx);
            }
        }
        return map;
    }

    private List<Object> parseArray() {
        List<Object> list = new ArrayList<>();
        idx++; // Saltar '['
        skipWhitespace();

        if (idx < src.length() && src.charAt(idx) == ']') {
            idx++; // Array vacío
            return list;
        }

        while (idx < src.length()) {
            list.add(parseValue());
            skipWhitespace();

            char next = src.charAt(idx);
            if (next == ']') {
                idx++;
                break;
            } else if (next == ',') {
                idx++;
            } else {
                throw new IllegalArgumentException("Se esperaba ',' o ']' en " + idx);
            }
        }
        return list;
    }

    private String parseString() {
        idx++; // Saltar comilla inicial '"'
        int start = idx;
        while (idx < src.length()) {
            char c = src.charAt(idx);
            // Manejo básico de escape (ej. \")
            if (c == '\\') {
                idx += 2;
                continue;
            }
            if (c == '"') {
                String val = src.substring(start, idx);
                idx++; // Saltar comilla final '"'
                return val; // Nota: En producción querrías des-escapar caracteres como \n o \"
            }
            idx++;
        }
        throw new IllegalArgumentException("String sin cerrar al final del JSON");
    }

    private Number parseNumber() {
        int start = idx;
        if (src.charAt(idx) == '-') idx++;
        boolean isFloat = false;

        while (idx < src.length()) {
            char c = src.charAt(idx);
            if (Character.isDigit(c)) {
                idx++;
            } else if (c == '.' || c == 'e' || c == 'E') {
                isFloat = true;
                idx++;
            } else {
                break;
            }
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
        throw new IllegalArgumentException("Error parseando booleano en " + idx);
    }

    private Object parseNull() {
        if (src.startsWith("null", idx)) {
            idx += 4;
            return null;
        }
        throw new IllegalArgumentException("Error parseando null en " + idx);
    }

    private void skipWhitespace() {
        while (idx < src.length() && Character.isWhitespace(src.charAt(idx))) {
            idx++;
        }
    }

    // === DEMOSTRACIÓN DE USO ===
    @SuppressWarnings("unchecked")
    public static void main(String[] args) {
        String json = """
            {
                "success": true,
                "nullValue": null,
                "maxConnections": 50,
                "hosts": ["192.168.1.1", "10.0.0.5"],
                "meta": {
                    "version": 1.2
                }
            }
            """;
        String jsonCompacto = "{\"success\":true,\"hosts\":[\"192.168.1.1\",\"10.0.0.5\"],\"meta\":{\"version\":1.2}}";
        String jsonSuperIndentado = """
    {
                    "success"       :        true,
        
        "hosts"   :   [
                                    "192.168.1.1",
                                    "10.0.0.5"
        ],
        
                    "meta" : {
                                                    "version" : 1.2
                    }
    }
    """;



        // Parsear a un Mapa genérico
        Map<String, Object> root = (Map<String, Object>) VanillaJsonParser.parse(jsonSuperIndentado);

        // 1. Extraer tipos primitivos y nulls
        Boolean success = (Boolean) root.get("success");
        Object nullVal = root.get("nullValue");
        Number maxConn = (Number) root.get("maxConnections");

        // 2. Extraer una lista (El caso exacto que querías)
        List<String> hosts = (List<String>) root.get("hosts");

        // 3. Extraer objetos anidados
        Map<String, Object> meta = (Map<String, Object>) root.get("meta");
        Double version = (Double) meta.get("version");

        // Resultados
        System.out.println("Success: " + success);         // true
        System.out.println("Null: " + nullVal);            // null
        System.out.println("Max Conn: " + maxConn);        // 50
        System.out.println("Hosts list: " + hosts);        //
        System.out.println("Meta version: " + version);    // 1.2
    }
}
