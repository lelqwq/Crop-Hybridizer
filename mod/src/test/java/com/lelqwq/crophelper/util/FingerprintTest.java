package com.lelqwq.crophelper.util;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import org.junit.Test;

import com.lelqwq.crophelper.catalog.Species;

public class FingerprintTest {

    private static Species species(String name, int tier, int[] stats, String... attributes) {
        return new Species("test", name, name, tier, stats, attributes, 4);
    }

    private static final int[] STATS = new int[] { 1, 2, 3, 4, 5 };

    @Test
    public void sameCatalogAndModsProduceSameFingerprint() {
        List<Species> first = Arrays.asList(species("a", 1, STATS), species("b", 2, STATS));
        List<Species> second = Arrays.asList(species("b", 2, STATS), species("a", 1, STATS));
        assertEquals(Fingerprint.compute(first, "IC2=1"), Fingerprint.compute(second, "IC2=1"));
    }

    @Test
    public void changedStatsChangeFingerprint() {
        Species before = species("a", 1, STATS);
        Species after = species("a", 1, new int[] { 1, 2, 3, 4, 6 });
        assertNotEquals(
            Fingerprint.compute(Collections.singletonList(before), "IC2=1"),
            Fingerprint.compute(Collections.singletonList(after), "IC2=1"));
    }

    @Test
    public void changedModVersionsChangeFingerprint() {
        List<Species> catalog = Collections.singletonList(species("a", 1, STATS));
        assertNotEquals(Fingerprint.compute(catalog, "IC2=1"), Fingerprint.compute(catalog, "IC2=2"));
    }

    @Test
    public void displayNameDoesNotAffectFingerprint() {
        Species first = new Species("test", "a", "Display A", 1, STATS, new String[0], 4);
        Species second = new Species("test", "a", "Display B", 1, STATS, new String[0], 4);
        assertEquals(
            Fingerprint.compute(Collections.singletonList(first), "IC2=1"),
            Fingerprint.compute(Collections.singletonList(second), "IC2=1"));
    }
}
