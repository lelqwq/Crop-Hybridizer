package com.lelqwq.crophelper.rules;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import com.lelqwq.crophelper.catalog.Species;

public class CrossingRulesTest {

    private static Species species(String name, int tier, int[] stats, String... attributes) {
        return new Species("test", name, name, tier, stats, attributes, 4);
    }

    private static int[] stats(int value) {
        return new int[] { value, value, value, value, value };
    }

    @Test
    public void sameSpeciesHasBaseWeight() {
        Species value = species("same", 4, stats(10));
        assertEquals(500, CrossingRules.ratio(value, value));
    }

    @Test
    public void identicalStatsWithoutAttributesGiveTen() {
        Species candidate = species("candidate", 4, stats(10));
        Species parent = species("parent", 4, stats(10));
        assertEquals(10, CrossingRules.ratio(candidate, parent));
    }

    @Test
    public void statDifferenceReducesWeight() {
        Species candidate = species("candidate", 4, new int[] { 3, 1, 1, 1, 1 });
        Species parent = species("parent", 4, new int[] { 1, 1, 1, 1, 1 });
        // 第一项差 2：2 - 2 = 0；其余四项各 2，合计 8。
        assertEquals(8, CrossingRules.ratio(candidate, parent));
    }

    @Test
    public void matchingAttributesAreCaseInsensitiveAndCountEveryPair() {
        Species candidate = species("candidate", 4, stats(1), "Red", "blue");
        Species parent = species("parent", 4, stats(1), "red", "BLUE");
        // 基础 10 + 2 个匹配对 * 5 = 20。
        assertEquals(20, CrossingRules.ratio(candidate, parent));
    }

    @Test
    public void duplicateAttributesCountRepeatedly() {
        Species candidate = species("candidate", 4, stats(1), "x", "x");
        Species parent = species("parent", 4, stats(1), "X");
        // 基础 10 + 2 个匹配对 * 5 = 20。
        assertEquals(20, CrossingRules.ratio(candidate, parent));
    }

    @Test
    public void higherTierIsPenalized() {
        Species candidate = species("candidate", 5, stats(1));
        Species parent = species("parent", 2, stats(1));
        // 基础 10 - 2 * 3 = 4。
        assertEquals(4, CrossingRules.ratio(candidate, parent));
    }

    @Test
    public void muchLowerTierIsPenalized() {
        Species candidate = species("candidate", 1, stats(1));
        Species parent = species("parent", 5, stats(1));
        // 基础 10 + (-4) = 6。
        assertEquals(6, CrossingRules.ratio(candidate, parent));
    }

    @Test
    public void tierBoundariesDoNotTriggerPenalty() {
        // IC2 使用 diff > 1 与 diff < -3，边界本身不调整。
        assertEquals(10, CrossingRules.ratio(species("candidate", 2, stats(1)), species("parent", 1, stats(1))));
        assertEquals(10, CrossingRules.ratio(species("candidate", 1, stats(1)), species("parent", 4, stats(1))));
    }

    @Test
    public void tierDifferenceOfTwoIsPenalized() {
        Species candidate = species("candidate", 4, stats(1));
        Species parent = species("parent", 2, stats(1));
        // 基础 10 - 2 * 2 = 6。
        assertEquals(6, CrossingRules.ratio(candidate, parent));
    }

    @Test
    public void weightIsNeverNegative() {
        Species candidate = species("candidate", 4, stats(31));
        Species parent = species("parent", 4, stats(0));
        assertEquals(0, CrossingRules.ratio(candidate, parent));
    }

    @Test
    public void twoParentsAddTheirWeights() {
        Species candidate = species("candidate", 4, stats(10));
        Species first = species("first", 4, stats(10));
        Species second = species("second", 4, stats(10));
        assertEquals(20, CrossingRules.totalWeight(candidate, first, second));
    }

    @Test
    public void identicalParentsDoubleTheSameSpeciesWeight() {
        Species parent = species("parent", 4, stats(10));
        assertEquals(1000, CrossingRules.totalWeight(parent, parent, parent));
    }

    @Test
    public void candidateWeightsFormCompleteDenominator() {
        Species first = species("first", 2, stats(5), "green");
        Species second = species("second", 3, stats(7), "green");
        Species[] candidates = new Species[] { first, second, species("third", 2, stats(5), "green") };

        long total = 0;
        for (Species candidate : candidates) {
            total += CrossingRules.totalWeight(candidate, first, second);
        }
        assertTrue(total > 0);

        double sum = 0;
        for (Species candidate : candidates) {
            sum += CrossingRules.totalWeight(candidate, first, second) / (double) total;
        }
        assertEquals(1.0d, sum, 1e-9);
    }
}
