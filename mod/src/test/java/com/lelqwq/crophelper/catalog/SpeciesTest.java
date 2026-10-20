package com.lelqwq.crophelper.catalog;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class SpeciesTest {

    @Test
    public void usesOwnerAndNameAsId() {
        Species species = new Species("IC2", "rubber", null, 2, new int[] { 1, 2, 3, 4, 5 }, null, 4);
        assertEquals("IC2:rubber", species.id);
        assertEquals("rubber", species.displayName);
        assertEquals(0, species.attributes().length);
    }

    @Test
    public void filtersNullAttributes() {
        Species species = new Species(
            "test",
            "crop",
            "Crop",
            2,
            new int[] { 1, 2, 3, 4, 5 },
            new String[] { "green", null, "edible" },
            4);
        assertEquals(2, species.attributes().length);
        assertEquals("green", species.attributes()[0]);
        assertEquals("edible", species.attributes()[1]);
    }
}
