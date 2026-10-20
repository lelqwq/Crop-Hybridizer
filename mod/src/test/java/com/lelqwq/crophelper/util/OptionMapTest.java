package com.lelqwq.crophelper.util;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

import org.junit.Test;

public class OptionMapTest {

    @Test
    public void keepsStringKeys() {
        Map<String, Object> input = new HashMap<String, Object>();
        input.put("crop_helper", "info");
        input.put("protocol", Long.valueOf(1L));

        Map<String, Object> result = OptionMap.normalize(input);
        assertEquals("info", result.get("crop_helper"));
        assertEquals(Long.valueOf(1L), result.get("protocol"));
    }

    @Test
    public void decodesByteArrayKeys() {
        Map<Object, Object> input = new HashMap<Object, Object>();
        input.put("crop_helper".getBytes(StandardCharsets.UTF_8), "info");

        Map<String, Object> result = OptionMap.normalize(input);
        assertEquals("info", result.get("crop_helper"));
    }

    @Test
    public void ignoresNonStringKeys() {
        Map<Object, Object> input = new HashMap<Object, Object>();
        input.put(Long.valueOf(1L), "value");

        Map<String, Object> result = OptionMap.normalize(input);
        assertFalse(result.containsKey("1"));
        assertEquals(0, result.size());
    }
}
