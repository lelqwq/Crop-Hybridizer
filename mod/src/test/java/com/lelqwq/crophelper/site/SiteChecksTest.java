package com.lelqwq.crophelper.site;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.util.Arrays;
import java.util.Collections;

import org.junit.Test;

public class SiteChecksTest {

    @Test
    public void mapsAllFourRobotOrientations() {
        int[][] directions = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } };
        int[][] left = { { 9, 124, 19 }, { 11, 124, 19 }, { 11, 124, 21 }, { 9, 124, 21 } };
        int[][] right = { { 11, 124, 19 }, { 11, 124, 21 }, { 9, 124, 21 }, { 9, 124, 19 } };
        for (int i = 0; i < directions.length; i++) {
            int[] d = directions[i];
            int x = 10 + d[0];
            int z = 20 + d[1];
            int[][] p = SiteChecks.positions(10, 124, 20, x, 124, z);
            assertArrayEquals(new int[] { x, 124, z }, p[0]);
            assertArrayEquals(left[i], p[1]);
            assertArrayEquals(right[i], p[2]);
            assertArrayEquals(new int[] { x + d[0], 124, z + d[1] }, p[3]);
            assertArrayEquals(new int[] { 10, 124, 20 }, p[4]);
        }
    }

    @Test
    public void parentOrderMaySwapButSpeciesAndMultiplicityMustMatch() {
        assertTrue(SiteChecks.parentsMatch("A", "B", "A", "B"));
        assertTrue(SiteChecks.parentsMatch("B", "A", "A", "B"));
        assertTrue(SiteChecks.parentsMatch("A", "A", "A", "A"));
        assertFalse(SiteChecks.parentsMatch("A", "B", "A", "A"));
        assertFalse(SiteChecks.parentsMatch("A", "C", "A", "B"));
        assertFalse(SiteChecks.parentsMatch(null, "B", "A", "B"));
    }

    @Test
    public void refusesVerticalRemoteDiagonalAndOverflowCoordinates() {
        int[][] bad = { { 0, 1, 0 }, { 0, 0, 0 }, { 0, 0, 2 }, { 1, 0, 1 } };
        for (int[] p : bad) {
            try {
                SiteChecks.positions(0, 0, 0, p[0], p[1], p[2]);
                fail("must reject non-adjacent horizontal targets");
            } catch (IllegalArgumentException expected) {}
        }
        try {
            SiteChecks.positions(Integer.MAX_VALUE, 0, 0, Integer.MIN_VALUE, 0, 0);
            fail("integer wraparound is not adjacency");
        } catch (IllegalArgumentException expected) {}
    }

    @Test
    public void unknownNeverBecomesReadyAndBlockedTakesPrecedence() {
        assertEquals("unknown", SiteChecks.status(Collections.emptyList()));
        assertEquals("pass", SiteChecks.status(Arrays.asList(SiteChecks.check("a", "pass", "ok"))));
        assertEquals(
            "unknown",
            SiteChecks.status(
                Arrays.asList(SiteChecks.check("a", "pass", "ok"), SiteChecks.check("b", "unknown", "unreviewed"))));
        assertEquals(
            "blocked",
            SiteChecks.status(
                Arrays.asList(
                    SiteChecks.check("a", "unknown", "unreviewed"),
                    SiteChecks.check("b", "blocked", "immature"))));
    }
}
