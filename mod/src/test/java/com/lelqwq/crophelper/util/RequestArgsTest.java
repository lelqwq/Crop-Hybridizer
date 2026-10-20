package com.lelqwq.crophelper.util;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;

import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

import org.junit.Test;

import com.lelqwq.crophelper.ApiException;

public class RequestArgsTest {

    @Test
    public void acceptsIntegralDouble() {
        Map<String, Object> args = new HashMap<String, Object>();
        args.put("offset", Double.valueOf(3.0d));
        assertEquals(3, RequestArgs.optionalInt(args, "offset", 0, 0, 100));
    }

    @Test
    public void acceptsLong() {
        Map<String, Object> args = new HashMap<String, Object>();
        args.put("protocol", Long.valueOf(1L));
        assertEquals(1, RequestArgs.requiredInt(args, "protocol", 0, 100));
    }

    @Test
    public void rejectsNonIntegralNumber() {
        Map<String, Object> args = new HashMap<String, Object>();
        args.put("offset", Double.valueOf(1.5d));
        expectInvalid(args, "offset");
    }

    @Test
    public void rejectsNegativeOffset() {
        Map<String, Object> args = new HashMap<String, Object>();
        args.put("offset", Long.valueOf(-1L));
        expectInvalid(args, "offset");
    }

    @Test
    public void rejectsLimitAboveMaximum() {
        Map<String, Object> args = new HashMap<String, Object>();
        args.put("limit", Long.valueOf(65L));
        expectInvalid(args, "limit");
    }

    @Test
    public void rejectsStringNumber() {
        Map<String, Object> args = new HashMap<String, Object>();
        args.put("offset", "3");
        expectInvalid(args, "offset");
    }

    @Test
    public void rejectsMissingRequiredValue() {
        try {
            RequestArgs.requiredInt(new HashMap<String, Object>(), "protocol", 0, 100);
            fail("expected ApiException");
        } catch (ApiException e) {
            assertEquals("invalid_argument", e.code());
        }
    }

    @Test
    public void usesDefaultWhenOptionalValueIsMissing() {
        assertEquals(32, RequestArgs.optionalInt(new HashMap<String, Object>(), "limit", 32, 1, 64));
    }

    @Test
    public void acceptsUtf8BytesAsString() {
        Map<String, Object> args = new HashMap<String, Object>();
        args.put("species_id", "IC2:rubber".getBytes(StandardCharsets.UTF_8));
        assertEquals("IC2:rubber", RequestArgs.requiredString(args, "species_id"));
    }

    @Test
    public void preservesSurroundingWhitespaceInIds() {
        Map<String, Object> args = new HashMap<String, Object>();
        args.put("species_id", " A:one ");
        assertEquals(" A:one ", RequestArgs.requiredString(args, "species_id"));
    }

    @Test
    public void requiresNonEmptyString() {
        Map<String, Object> args = new HashMap<String, Object>();
        args.put("species_id", "   ");
        try {
            RequestArgs.requiredString(args, "species_id");
            fail("expected ApiException");
        } catch (ApiException e) {
            assertEquals("invalid_argument", e.code());
        }
    }

    private static void expectInvalid(Map<String, Object> args, String key) {
        int max = "limit".equals(key) ? 64 : Integer.MAX_VALUE;
        try {
            RequestArgs.optionalInt(args, key, 0, 0, max);
            fail("expected ApiException");
        } catch (ApiException e) {
            assertEquals("invalid_argument", e.code());
        }
    }
}
